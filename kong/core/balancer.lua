local cache = require "kong.tools.database_cache"
local pl_tablex = require "pl.tablex"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local dns_client = require "resty.dns.client"  -- due to startup/require order, cannot use the one from 'singletons' here
local ring_balancer = require "resty.dns.balancer"

local toip = dns_client.toip
local log = ngx.log

local ERROR = ngx.ERR
local DEBUG = ngx.DEBUG
local EMPTY_T = pl_tablex.readonly {}

--===========================================================
-- Ring-balancer based resolution
--===========================================================
local balancers = {}  -- table holding our balancer objects, indexed by upstream name

-- caching logic;
-- we retain 3 entities:
-- 1) list of upstreams: to be invalidated on any upstream change
-- 2) individual upstreams: to be invalidated on individual basis
-- 3) target history for an upstream, invalidated when:
--    a) along with the upstream it belongs to
--    b) upon any target change for the upstream (can only add entries)
-- Distinction between 1 and 2 makes it possible to invalidate individual
-- upstreams, instead of all at once forcing to rebuild all balancers

-- Implements a simple dictionary with all upstream-ids indexed
-- by their name.
local function load_upstreams_dict_into_memory()
  log(DEBUG, "fetching all upstreams")
  local upstreams, err = singletons.dao.upstreams:find_all()
  if err then
    return nil, err
  end

  -- build a dictionary, indexed by the upstream name
  local upstreams_dict = {}
  for _, up in ipairs(upstreams) do
    upstreams_dict[up.name] = up.id
  end

  -- check whether any of our existing balancers has been deleted
  for upstream_name in pairs(balancers) do
    if not upstreams_dict[upstream_name] then
      -- this one was deleted, so also clear the balancer object
      balancers[upstream_name] = nil
    end
  end

  return upstreams_dict
end

-- delete a balancer object from our internal cache
local function invalidate_balancer(upstream_name)
  balancers[upstream_name] = nil
end

-- loads a single upstream entity
local function load_upstream_into_memory(upstream_id)
  log(DEBUG, "fetching upstream: ", tostring(upstream_id))

  local upstream, err = singletons.dao.upstreams:find_all {id = upstream_id}
  if not upstream then
    return nil, err
  end

  return upstream[1]  -- searched by id, so only 1 row in the returned set
end

-- finds and returns an upstream entity. This functions covers
-- caching, invalidation, db access, et al.
-- @return upstream table, or `false` if not found, or nil+error
local function get_upstream(upstream_name)
  local upstreams_dict, err = cache.get_or_set(cache.upstreams_dict_key(),
                              nil, load_upstreams_dict_into_memory)
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[upstream_name]
  if not upstream_id then
    return false -- no upstream by this name
  end

  return cache.get_or_set(cache.upstream_key(upstream_id), nil,
                          load_upstream_into_memory, upstream_id)
end

-- loads the target history for an upstream
-- @param upstream_id Upstream uuid for which to load the target history
local function load_targets_into_memory(upstream_id)
  log(DEBUG, "fetching targets for upstream: ",tostring(upstream_id))

  local target_history, err = singletons.dao.targets:find_all {upstream_id = upstream_id}
  if err then return nil, err end

  -- perform some raw data updates
  for _, target in ipairs(target_history) do
    -- split `target` field into `name` and `port`
    local port
    target.name, port = string.match(target.target, "^(.-):(%d+)$")
    target.port = tonumber(port)

    -- need exact order, so create sort-key by created-time and uuid
    target.order = target.created_at .. ":" .. target.id
  end

  table.sort(target_history, function(a,b)
    return a.order < b.order
  end)

  return target_history
end

-- applies the history of lb transactions from index `start` forward
-- @param rb ring-balancer object
-- @param history list of targets/transactions to be applied
-- @param start the index where to start in the `history` parameter
-- @return true
local function apply_history(rb, history, start)

  for i = start, #history do
    local target = history[i]

    if target.weight > 0 then
      assert(rb:addHost(target.name, target.port, target.weight))
    else
      assert(rb:removeHost(target.name, target.port))
    end

    rb.__targets_history[i] = {
      name = target.name,
      port = target.port,
      weight = target.weight,
      order = target.order,
    }
  end

  return true
end

-- looks up a balancer for the target.
-- @param target the table with the target details
-- @return balancer if found, or `false` if not found, or nil+error on error
local get_balancer = function(target)
  -- NOTE: only called upon first lookup, so `cache_only` limitations do not apply here
  local hostname = target.host

  -- first go and find the upstream object, from cache or the db
  local upstream, err = get_upstream(hostname)

  if upstream == false then
    return false                -- no upstream by this name
  end

  if err then
    return nil, err             -- there was an error
  end

  -- we've got the upstream, now fetch its targets, from cache or the db
  local targets_history, err = cache.get_or_set(cache.targets_key(upstream.id),
                               nil, load_targets_into_memory, upstream.id)
  if err then
    return nil, err
  end

  local balancer = balancers[upstream.name]
  if not balancer then
    -- no balancer yet (or invalidated) so create a new one
    balancer, err = ring_balancer.new({
        wheelsize = upstream.slots,
        order = upstream.orderlist,
        dns = dns_client,
      })

    if not balancer then
      return balancer, err
    end

    -- NOTE: we're inserting a foreign entity in the balancer, to keep track of
    -- target-history changes!
    balancer.__targets_history = {}
    balancers[upstream.name] = balancer
  end

  -- check history state
  -- NOTE: in the code below variables are similarly named, but the
  -- ones with `__`-prefixed, are the ones on the `balancer` object, and the
  -- regular ones are the ones we just fetched and are comparing against.
  local __size = #balancer.__targets_history
  local size = #targets_history

  if __size ~= size or
    (balancer.__targets_history[__size] or EMPTY_T).order ~=
    (targets_history[size] or EMPTY_T).order then
    -- last entries in history don't match, so we must do some updates.

    -- compare balancer history with db-loaded history
    local last_equal_index = 0  -- last index where history is the same
    for i, entry in ipairs(balancer.__targets_history) do
      if entry.order ~= (targets_history[i] or EMPTY_T).order then
        last_equal_index = i - 1
        break
      end
    end

    if last_equal_index == __size then
      -- history is the same, so we only need to add new entries
      apply_history(balancer, targets_history, last_equal_index + 1)

    else
      -- history not the same.
      -- TODO: ideally we would undo the last ones until we're equal again
      -- and can replay changes, but not supported by ring-balancer yet.
      -- for now; create a new balancer from scratch
      balancer, err = ring_balancer.new({
          wheelsize = upstream.slots,
          order = upstream.orderlist,
          dns = dns_client,
        })
      if not balancer then return balancer, err end

      balancer.__targets_history = {}
      balancers[upstream.name] = balancer  -- overwrite our existing one
      apply_history(balancer, targets_history, 1)
    end
  end

  return balancer
end


--===========================================================
-- Main entry point when resolving
--===========================================================

-- Resolves the target structure in-place (fields `ip`, `port`, and `hostname`).
--
-- If the hostname matches an 'upstream' pool, then it must be balanced in that
-- pool, in this case any port number provided will be ignored, as the pool provides it.
--
-- @param target the data structure as defined in `core.access.before` where it is created
-- @return true on success, nil+error otherwise
local function execute(target)
  if target.type ~= "name" then
    -- it's an ip address (v4 or v6), so nothing we can do...
    target.ip = target.host
    target.port = target.port or 80 -- TODO: remove this fallback value
    target.hostname = target.host
    return true
  end

  -- when tries == 0 it runs before the `balancer` context (in the `access` context),
  -- when tries >= 2 then it performs a retry in the `balancer` context
  local dns_cache_only = target.try_count ~= 0
  local balancer

  if dns_cache_only then
    -- retry, so balancer is already set if there was one
    balancer = target.balancer

  else
    local err
    -- first try, so try and find a matching balancer/upstream object
    balancer, err = get_balancer(target)
    if err then -- check on err, `nil` without `err` means we do dns resolution
      return nil, err
    end

    -- store for retries
    target.balancer = balancer
  end

  if balancer then
    -- have to invoke the ring-balancer
    local hashValue = nil  -- TODO: implement, nil does simple round-robin

    local ip, port, hostname = balancer:getPeer(hashValue, nil, dns_cache_only)
    if not ip then
      if port == "No peers are available" then
        -- in this case a "503 service unavailable", others will be a 500.
        log(ERROR, "failure to get a peer from the ring-balancer '",
                   target.host, "': ", port)
        return responses.send(503)
      end

      return nil, port -- some other error
    end

    target.ip = ip
    target.port = port
    target.hostname = hostname
    return true
  end

  -- have to do a regular DNS lookup
  local ip, port = toip(target.host, target.port, dns_cache_only)
  if not ip then
    if port == "dns server error; 3 name error" then
      -- in this case a "503 service unavailable", others will be a 500.
      log(ERROR, "name resolution failed for '", tostring(target.host),
                 "': ", port)
      return responses.send(503)
    end
    return nil, port
  end

  target.ip = ip
  target.port = port
  target.hostname = target.host
  return true
end

return {
  execute = execute,
  invalidate_balancer = invalidate_balancer,

  -- ones below are exported for test purposes
  _load_upstreams_dict_into_memory = load_upstreams_dict_into_memory,
  _load_upstream_into_memory = load_upstream_into_memory,
  _load_targets_into_memory = load_targets_into_memory,
}
