local pl_tablex = require "pl.tablex"
local singletons = require "kong.singletons"
local utils = require "kong.tools.utils"

-- due to startup/require order, cannot use the ones from 'singletons' here
local dns_client = require "resty.dns.client"

local table_concat = table.concat
local crc32 = ngx.crc32_short
local toip = dns_client.toip
local log = ngx.log
local sleep = ngx.sleep
local min = math.min
local max = math.max

local CRIT  = ngx.CRIT
local ERR   = ngx.ERR
local WARN  = ngx.WARN
local DEBUG = ngx.DEBUG
local EMPTY_T = pl_tablex.readonly {}

-- for unit-testing purposes only
local _load_upstreams_dict_into_memory
local _load_upstream_into_memory
local _load_targets_into_memory


--==============================================================================
-- Ring-balancer based resolution
--==============================================================================


-- table holding our balancer objects, indexed by upstream id
local balancers = {}


-- objects whose lifetimes are bound to that of a balancer
local healthcheckers = {}
local healthchecker_callbacks = {}
local target_histories = {}
local upstream_ids = {}


-- health check API callbacks to be called on healthcheck events
local healthcheck_subscribers = {}


-- Caching logic
--
-- We retain 3 entities in singletons.cache:
--
-- 1) `"balancer:upstreams"` - a list of upstreams
--    to be invalidated on any upstream change
-- 2) `"balancer:upstreams:" .. id` - individual upstreams
--    to be invalidated on individual basis
-- 3) `"balancer:targets:" .. id`
--    target history for an upstream, invalidated:
--    a) along with the upstream it belongs to
--    b) upon any target change for the upstream (can only add entries)
--
-- Distinction between 1 and 2 makes it possible to invalidate individual
-- upstreams, instead of all at once forcing to rebuild all balancers


local function set_balancer(upstream_id, balancer)
  local prev = balancers[upstream_id]
  if prev then
    healthcheckers[prev] = nil
    healthchecker_callbacks[prev] = nil
    target_histories[prev] = nil
    upstream_ids[prev] = nil
  end
  balancers[upstream_id] = balancer
end


local function stop_healthchecker(balancer)
  local healthchecker = healthcheckers[balancer]
  if healthchecker then
    local ok, err = healthchecker:clear()
    if not ok then
      log(ERR, "[healthchecks] error clearing healthcheck data: ", err)
    end
    healthchecker:stop()
    local hc_callback = healthchecker_callbacks[balancer]
    singletons.worker_events.unregister(hc_callback, healthchecker.EVENT_SOURCE)
  end
  healthcheckers[balancer] = nil
end


local get_upstream_by_id
do
  ------------------------------------------------------------------------------
  -- Loads a single upstream entity.
  -- @param upstream_id string
  -- @return the upstream table, or nil+error
  local function load_upstream_into_memory(upstream_id)
    log(DEBUG, "fetching upstream: ", tostring(upstream_id))

    local upstream, err = singletons.db.upstreams:select({id = upstream_id})
    if not upstream then
      return nil, err
    end

    return upstream
  end
  _load_upstream_into_memory = load_upstream_into_memory

  get_upstream_by_id = function(upstream_id)
    local upstream_cache_key = "balancer:upstreams:" .. upstream_id
    return singletons.core_cache:get(upstream_cache_key, nil,
                                load_upstream_into_memory, upstream_id)
  end
end


local fetch_target_history
do
  ------------------------------------------------------------------------------
  -- Loads the target history from the DB.
  -- @param upstream_id Upstream uuid for which to load the target history
  -- @return The target history array, with target entity tables.
  local function load_targets_into_memory(upstream_id)
    log(DEBUG, "fetching targets for upstream: ", tostring(upstream_id))

    local target_history, err, err_t =
      singletons.db.targets:select_by_upstream_raw({ id = upstream_id })

    if not target_history then
      return nil, err, err_t
    end

    -- perform some raw data updates
    for _, target in ipairs(target_history) do
      -- split `target` field into `name` and `port`
      local port
      target.name, port = string.match(target.target, "^(.-):(%d+)$")
      target.port = tonumber(port)
    end

    return target_history
  end
  _load_targets_into_memory = load_targets_into_memory


  ------------------------------------------------------------------------------
  -- Fetch target history, from cache or the DB.
  -- @param upstream The upstream entity object
  -- @return The target history array, with target entity tables.
  fetch_target_history = function(upstream)
    local targets_cache_key = "balancer:targets:" .. upstream.id
    return singletons.core_cache:get(targets_cache_key, nil,
                                load_targets_into_memory, upstream.id)
  end
end


--------------------------------------------------------------------------------
-- Applies the history of lb transactions from index `start` forward.
-- @param rb ring balancer object
-- @param history list of targets/transactions to be applied
-- @param start the index where to start in the `history` parameter
local function apply_history(rb, history, start)

  for i = start, #history do
    local target = history[i]

    if target.weight > 0 then
      assert(rb:addHost(target.name, target.port, target.weight))
    else
      assert(rb:removeHost(target.name, target.port))
    end

    target_histories[rb][i] = {
      name = target.name,
      port = target.port,
      weight = target.weight,
      order = target.order,
    }
  end
end


local function populate_healthchecker(hc, balancer, upstream)
  for weight, addr, host in balancer:addressIter() do
    if weight > 0 then
      local ipaddr = addr.ip
      local port = addr.port
      local ok, err = hc:add_target(ipaddr, port, host.hostname, true,
                                    upstream.host_header)
      if ok then
        -- Get existing health status which may have been initialized
        -- with data from another worker, and apply to the new balancer.
        local tgt_status = hc:get_target_status(ipaddr, port, host.hostname)
        if tgt_status ~= nil then
          balancer:setAddressStatus(tgt_status, ipaddr, port)
        end

      else
        log(ERR, "[healthchecks] failed adding target: ", err)
      end
    end
  end
end


local create_balancer
do
  local balancer_types = {
    ["consistent-hashing"] = require("resty.dns.balancer.ring"),
    ["least-connections"] = require("resty.dns.balancer.least_connections"),
    ["round-robin"] = require("resty.dns.balancer.ring"),
  }

  local create_healthchecker
  do
    local healthcheck -- delay initialization

    ------------------------------------------------------------------------------
    -- Callback function that informs the healthchecker when targets are added
    -- or removed to a balancer and when targets health status change.
    -- @param balancer the ring balancer object that triggers this callback.
    -- @param action "added", "removed", or "health"
    -- @param address balancer address object
    -- @param ip string
    -- @param port number
    -- @param hostname string
    local function ring_balancer_callback(balancer, action, address, ip, port, hostname)
      local healthchecker = healthcheckers[balancer]
      if not healthchecker then
        return
      end

      if action == "health" then
        local balancer_status
        if address then
          balancer_status = "HEALTHY"
        else
          balancer_status = "UNHEALTHY"
        end
        log(WARN, "[healthchecks] balancer ", healthchecker.name,
            " reported health status changed to ", balancer_status)

      else
        local upstream_id = upstream_ids[balancer]
        local upstream = get_upstream_by_id(upstream_id)

        if action == "added" then
          local ok, err = healthchecker:add_target(ip, port, hostname, true,
                                                  upstream.host_header)
          if not ok then
            log(ERR, "[healthchecks] failed adding a target: ", err)
          end

        elseif action == "removed" then
          local ok, err = healthchecker:remove_target(ip, port, hostname)
          if not ok then
            log(ERR, "[healthchecks] failed removing a target: ", err)
          end

        else
          log(WARN, "[healthchecks] unknown status from balancer: ",
                    tostring(action))
        end

      end
    end

    -- @param hc The healthchecker object
    -- @param balancer The balancer object
    -- @param upstream_id The upstream id
    local function attach_healthchecker_to_balancer(hc, balancer, upstream_id)
      local hc_callback = function(tgt, event)
        local status
        if event == hc.events.healthy then
          status = true
        elseif event == hc.events.unhealthy then
          status = false
        else
          return
        end

        local hostname = tgt.hostname
        local ok, err
        ok, err = balancer:setAddressStatus(status, tgt.ip, tgt.port, hostname)

        local health = status and "healthy" or "unhealthy"
        for _, subscriber in ipairs(healthcheck_subscribers) do
          subscriber(upstream_id, tgt.ip, tgt.port, hostname, health)
        end

        if not ok then
          log(ERR, "[healthchecks] failed setting peer status (upstream: ", hc.name, "): ", err)
        end
      end

      -- Register event using a weak-reference in worker-events,
      -- and attach lifetime of callback to that of the balancer.
      singletons.worker_events.register_weak(hc_callback, hc.EVENT_SOURCE)
      healthchecker_callbacks[balancer] = hc_callback

      -- The lifetime of the healthchecker is based on that of the balancer.
      healthcheckers[balancer] = hc

      balancer.report_http_status = function(handle, status)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_http_status(ip, port, hostname, status, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end

      balancer.report_tcp_failure = function(handle)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_tcp_failure(ip, port, hostname, nil, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end

      balancer.report_timeout = function(handle)
        local ip, port = handle.address.ip, handle.address.port
        local hostname = handle.address.host and handle.address.host.hostname or nil
        local _, err = hc:report_timeout(ip, port, hostname, "passive")
        if err then
          log(ERR, "[healthchecks] failed reporting status: ", err)
        end
      end
    end

    ----------------------------------------------------------------------------
    -- Create a healthchecker object.
    -- @param upstream An upstream entity table.
    create_healthchecker = function(balancer, upstream)
      if not healthcheck then
        healthcheck = require("resty.healthcheck") -- delayed initialization
      end

      -- Do not run active healthchecks in `stream` module
      local checks = upstream.healthchecks
      if (ngx.config.subsystem == "stream" and checks.active.type ~= "tcp")
         or (ngx.config.subsystem == "http" and checks.active.type == "tcp")
      then
        checks = pl_tablex.deepcopy(checks)
        checks.active.healthy.interval = 0
        checks.active.unhealthy.interval = 0
      end

      local healthchecker, err = healthcheck.new({
        name = upstream.name,
        shm_name = "kong_healthchecks",
        checks = checks,
      })

      if not healthchecker then
        return nil, err
      end

      populate_healthchecker(healthchecker, balancer, upstream)

      attach_healthchecker_to_balancer(healthchecker, balancer, upstream.id)

      -- only enable the callback after the target history has been replayed.
      balancer:setCallback(ring_balancer_callback)

      return true
    end
  end

  local creating = {}

  local function wait(id)
    local timeout = 30
    local step = 0.001
    local ratio = 2
    local max_step = 0.5
    while timeout > 0 do
      sleep(step)
      timeout = timeout - step
      if not creating[id] then
        return true
      end
      if timeout <= 0 then
        break
      end
      step = min(max(0.001, step * ratio), timeout, max_step)
    end
    return nil, "timeout"
  end

  ------------------------------------------------------------------------------
  -- The mutually-exclusive section used internally by the
  -- 'create_balancer' operation.
  -- @param upstream (table) A db.upstreams entity
  -- @param history (table, optional) history of target updates
  -- @param start (integer, optional) from where to start reading the history
  -- @return The new balancer object, or nil+error
  local function create_balancer_exclusive(upstream, history, start)
    local health_threshold = upstream.healthchecks and
                              upstream.healthchecks.threshold or nil

    local balancer, err = balancer_types[upstream.algorithm].new({
      log_prefix = "upstream:" .. upstream.name,
      wheelSize = upstream.slots,  -- will be ignored by least-connections
      dns = dns_client,
      healthThreshold = health_threshold,
    })
    if not balancer then
      return nil, "failed creating balancer:" .. err
    end

    singletons.core_cache:invalidate_local("balancer:upstreams:" .. upstream.id)
    singletons.core_cache:invalidate_local("balancer:targets:" .. upstream.id)

    target_histories[balancer] = {}

    if not history then
      history, err = fetch_target_history(upstream)
      if not history then
        return nil, "failed fetching target history:" .. err
      end
      start = 1
    end

    apply_history(balancer, history, start)

    upstream_ids[balancer] = upstream.id

    local ok, err = create_healthchecker(balancer, upstream)
    if not ok then
      log(ERR, "[healthchecks] error creating health checker: ", err)
    end

    -- only make the new balancer available for other requests after it
    -- is fully set up.
    set_balancer(upstream.id, balancer)

    return balancer
  end

  ------------------------------------------------------------------------------
  -- Create a balancer object, its healthchecker and attach them to the
  -- necessary data structures. The creation of the balancer happens in a
  -- per-worker mutual exclusion section, such that no two requests create the
  -- same balancer at the same time.
  -- @param upstream (table) A db.upstreams entity
  -- @param recreate (boolean, optional) create new balancer even if one exists
  -- @param history (table, optional) history of target updates
  -- @param start (integer, optional) from where to start reading the history
  -- @return The new balancer object, or nil+error
  create_balancer = function(upstream, recreate, history, start)

    if balancers[upstream.id] and not recreate then
      return balancers[upstream.id]
    end

    if creating[upstream.id] then
      local ok = wait(upstream.id)
      if not ok then
        return nil, "timeout waiting for balancer for " .. upstream.id
      end
      return balancers[upstream.id]
    end

    creating[upstream.id] = true

    local balancer, err = create_balancer_exclusive(upstream, history, start)

    creating[upstream.id] = nil

    return balancer, err
  end
end


--------------------------------------------------------------------------------
-- Compare the target history of the upstream with that of the
-- current balancer object, updating or recreating the balancer if necessary.
-- @param upstream The upstream entity object
-- @param balancer The ring balancer object
-- @return true if all went well, or nil + error in case of failures.
local function check_target_history(upstream, balancer)
  -- Fetch the upstream's targets, from cache or the db
  local new_history, err = fetch_target_history(upstream)
  if err then
    return nil, err
  end

  local old_history = target_histories[balancer]

  -- check history state
  local old_size = #old_history
  local new_size = #new_history

  -- compare balancer history with db-loaded history
  local last_equal_index = 0  -- last index where history is the same
  for i, entry in ipairs(old_history) do
    local new_entry = new_history[i]
    if new_entry and
       new_entry.name == entry.name and
       new_entry.port == entry.port and
       new_entry.weight == entry.weight
    then
      last_equal_index = i
    else
      break
    end
  end

  if last_equal_index == new_size and new_size == old_size then
    -- No history update is necessary in the balancer object.
    return true
  elseif last_equal_index == old_size then
    -- history is the same, so we only need to add new entries
    apply_history(balancer, new_history, last_equal_index + 1)
    return true
  end

  -- history not the same.
  -- TODO: ideally we would undo the last ones until we're equal again
  -- and can replay changes, but not supported by ring-balancer yet.
  -- for now; create a new balancer from scratch

  stop_healthchecker(balancer)

  local new_balancer, err = create_balancer(upstream, true, new_history, 1)
  if not new_balancer then
    return nil, err
  end

  return true
end


local get_all_upstreams
do
  local function load_upstreams_dict_into_memory()
    local upstreams_dict = {}
    -- build a dictionary, indexed by the upstream name
    for up, err in singletons.db.upstreams:each() do
      if err then
        log(CRIT, "could not obtain list of upstreams: ", err)
        return nil
      end

      upstreams_dict[up.name] = up.id
    end
    return upstreams_dict
  end
  _load_upstreams_dict_into_memory = load_upstreams_dict_into_memory


  local opts = { neg_ttl = 10 }


  ------------------------------------------------------------------------------
  -- Implements a simple dictionary with all upstream-ids indexed
  -- by their name.
  -- @return The upstreams dictionary (a map with upstream names as string keys
  -- and upstream entity tables as values), or nil+error
  get_all_upstreams = function()
    local upstreams_dict, err = singletons.core_cache:get("balancer:upstreams", opts,
                                                load_upstreams_dict_into_memory)
    if err then
      return nil, err
    end

    return upstreams_dict or {}
  end
end


------------------------------------------------------------------------------
-- Finds and returns an upstream entity. This function covers
-- caching, invalidation, db access, et al.
-- @param upstream_name string.
-- @return upstream table, or `false` if not found, or nil+error
local function get_upstream_by_name(upstream_name)
  local upstreams_dict, err = get_all_upstreams()
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[upstream_name]
  if not upstream_id then
    return false -- no upstream by this name
  end

  return get_upstream_by_id(upstream_id)
end


-- looks up a balancer for the target.
-- @param target the table with the target details
-- @param no_create (optional) if true, do not attempt to create
-- (for thorough testing purposes)
-- @return balancer if found, `false` if not found, or nil+error on error
local function get_balancer(target, no_create)
  -- NOTE: only called upon first lookup, so `cache_only` limitations
  -- do not apply here
  local hostname = target.host


  -- first go and find the upstream object, from cache or the db
  local upstream, err = get_upstream_by_name(hostname)
  if upstream == false then
    return false -- no upstream by this name
  end
  if err then
    return nil, err -- there was an error
  end

  local balancer = balancers[upstream.id]
  if not balancer then
    if no_create then
      return nil, "balancer not found"
    else
      log(ERR, "balancer not found for ", upstream.name, ", will create it")
      return create_balancer(upstream), upstream
    end
  end

  return balancer, upstream
end


--==============================================================================
-- Event Callbacks
--==============================================================================


local function do_target_event(operation, upstream_id, upstream_name)
  singletons.core_cache:invalidate_local("balancer:targets:" .. upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    log(ERR, "target ", operation, ": upstream not found for ", upstream_id)
    return
  end

  local balancer = balancers[upstream_id]
  if not balancer then
    log(ERR, "target ", operation, ": balancer not found for ", upstream_name)
    return
  end

  local ok, err = check_target_history(upstream, balancer)
  if not ok then
    log(ERR, "failed checking target history for ", upstream_name, ":  ", err)
  end
end

--------------------------------------------------------------------------------
-- Called on any changes to a target.
-- @param operation "create", "update" or "delete"
-- @param target Target table with `upstream.id` field
local function on_target_event(operation, target)

  if operation == "reset" then
    local upstreams = get_all_upstreams()
    for name, id in pairs(upstreams) do
      do_target_event("create", id, name)
    end

  else
    do_target_event(operation, target.upstream.id, target.upstream.name)

  end

end


-- Calculates hash-value.
-- Will only be called once per request, on first try.
-- @param upstream the upstream enity
-- @return integer value or nil if there is no hash to calculate
local create_hash = function(upstream, ctx)
  local hash_on = upstream.hash_on
  if hash_on == "none" or hash_on == nil or hash_on == ngx.null then
    return -- not hashing, exit fast
  end

  local identifier
  local header_field_name = "hash_on_header"

  for _ = 1,2 do

   if hash_on == "consumer" then
      if not ctx then
        ctx = ngx.ctx
      end

      -- consumer, fallback to credential
      identifier = (ctx.authenticated_consumer or EMPTY_T).id or
                   (ctx.authenticated_credential or EMPTY_T).id

    elseif hash_on == "ip" then
      identifier = ngx.var.remote_addr

    elseif hash_on == "header" then
      identifier = ngx.req.get_headers()[upstream[header_field_name]]
      if type(identifier) == "table" then
        identifier = table_concat(identifier)
      end

    elseif hash_on == "cookie" then
      identifier = ngx.var["cookie_" .. upstream.hash_on_cookie]

      -- If the cookie doesn't exist, create one and store in `ctx`
      -- to be added to the "Set-Cookie" header in the response
      if not identifier then
        if not ctx then
          ctx = ngx.ctx
        end

        identifier = utils.uuid()

        ctx.balancer_data.hash_cookie = {
          key = upstream.hash_on_cookie,
          value = identifier,
          path = upstream.hash_on_cookie_path
        }
      end

    end

    if identifier then
      return crc32(identifier)
    end

    -- we missed the first, so now try the fallback
    hash_on = upstream.hash_fallback
    header_field_name = "hash_fallback_header"
    if hash_on == "none" then
      return nil
    end
  end
  -- nothing found, leave without a hash
end


--==============================================================================
-- Initialize balancers
--==============================================================================


local function init()

  local upstreams, err = get_all_upstreams()
  if not upstreams then
    log(CRIT, "failed loading initial list of upstreams: ", err)
    return
  end

  local oks, errs = 0, 0
  for name, id in pairs(upstreams) do
    local upstream = get_upstream_by_id(id)
    local ok, err = create_balancer(upstream)
    if ok ~= nil then
      oks = oks + 1
    else
      log(CRIT, "failed creating balancer for ", name, ": ", err)
      errs = errs + 1
    end
  end
  log(DEBUG, "initialized ", oks, " balancer(s), ", errs, " error(s)")

end


local function do_upstream_event(operation, upstream_id, upstream_name)
  if operation == "create" then

    singletons.core_cache:invalidate_local("balancer:upstreams")

    local upstream = get_upstream_by_id(upstream_id)
    if not upstream then
      log(ERR, "upstream not found for ", upstream_id)
      return
    end

    local _, err = create_balancer(upstream)
    if err then
      log(CRIT, "failed creating balancer for ", upstream_name, ": ", err)
    end

  elseif operation == "delete" or operation == "update" then

    if singletons.db.strategy ~= "off" then
      singletons.core_cache:invalidate_local("balancer:upstreams")
      singletons.core_cache:invalidate_local("balancer:upstreams:" .. upstream_id)
      singletons.core_cache:invalidate_local("balancer:targets:"   .. upstream_id)
    end

    local balancer = balancers[upstream_id]
    if balancer then
      stop_healthchecker(balancer)
    end

    if operation == "delete" then
      set_balancer(upstream_id, nil)

    else
      local upstream = get_upstream_by_id(upstream_id)
      if not upstream then
        log(ERR, "upstream not found for ", upstream_id)
        return
      end

      local _, err = create_balancer(upstream, true)
      if err then
        log(ERR, "failed recreating balancer for ", upstream_name, ": ", err)
      end
    end

  end

end


--------------------------------------------------------------------------------
-- Called on any changes to an upstream.
-- @param operation "create", "update" or "delete"
-- @param upstream_data table with `id` and `name` fields
local function on_upstream_event(operation, upstream_data)

  if operation == "reset" then
    init()

  elseif operation == "delete_all" then
    local upstreams = get_all_upstreams()
    for name, id in pairs(upstreams) do
      do_upstream_event("delete", id, name)
    end

  else
    do_upstream_event(operation, upstream_data.id, upstream_data.name)

  end

end


--==============================================================================
-- Main entry point when resolving
--==============================================================================


--------------------------------------------------------------------------------
-- Resolves the target structure in-place (fields `ip`, `port`, and `hostname`).
--
-- If the hostname matches an 'upstream' pool, then it must be balanced in that
-- pool, in this case any port number provided will be ignored, as the pool
-- provides it.
--
-- @param target the data structure as defined in `core.access.before` where
-- it is created.
-- @return true on success, nil+error message+status code otherwise
local function execute(target, ctx)
  if target.type ~= "name" then
    -- it's an ip address (v4 or v6), so nothing we can do...
    target.ip = target.host
    target.port = target.port or 80 -- TODO: remove this fallback value
    target.hostname = target.host
    return true
  end

  -- when tries == 0,
  --   it runs before the `balancer` context (in the `access` context),
  -- when tries >= 2,
  --   then it performs a retry in the `balancer` context
  local dns_cache_only = target.try_count ~= 0
  local balancer, upstream, hash_value

  if dns_cache_only then
    -- retry, so balancer is already set if there was one
    balancer = target.balancer

  else
    -- first try, so try and find a matching balancer/upstream object
    balancer, upstream = get_balancer(target)
    if balancer == nil then -- `false` means no balancer, `nil` is error
      return nil, upstream, 500
    end

    if balancer then
      -- store for retries
      target.balancer = balancer

      -- calculate hash-value
      -- only add it if it doesn't exist, in case a plugin inserted one
      hash_value = target.hash_value
      if not hash_value then
        hash_value = create_hash(upstream, ctx)
        target.hash_value = hash_value
      end
    end
  end

  local ip, port, hostname, handle
  if balancer then
    -- have to invoke the ring-balancer
    ip, port, hostname, handle = balancer:getPeer(dns_cache_only,
                                          target.balancer_handle,
                                          hash_value)
    if not ip and
      (port == "No peers are available" or port == "Balancer is unhealthy") then
      return nil, "failure to get a peer from the ring-balancer", 503
    end
    target.hash_value = hash_value
    target.balancer_handle = handle

  else
    -- have to do a regular DNS lookup
    local try_list
    ip, port, try_list = toip(target.host, target.port, dns_cache_only)
    hostname = target.host
    if not ip then
      log(ERR, "DNS resolution failed: ", port, ". Tried: ", tostring(try_list))
      if port == "dns server error: 3 name error" or
         port == "dns client error: 101 empty record received" then
        return nil, "name resolution failed", 503
      end
    end
  end

  if not ip then
    return nil, port, 500
  end

  target.ip = ip
  target.port = port
  if upstream and upstream.host_header ~= nil then
    target.hostname = upstream.host_header
  else
    target.hostname = hostname
  end
  return true
end


--------------------------------------------------------------------------------
-- Update health status and broadcast to workers
-- @param upstream a table with upstream data: must have `name` and `id`
-- @param hostname target hostname
-- @param ip target entry. if nil updates all entries
-- @param port target port
-- @param is_healthy boolean: true if healthy, false if unhealthy
-- @return true if posting event was successful, nil+error otherwise
local function post_health(upstream, hostname, ip, port, is_healthy)

  local balancer = balancers[upstream.id]
  if not balancer then
    return nil, "Upstream " .. tostring(upstream.name) .. " has no balancer"
  end

  local healthchecker = healthcheckers[balancer]
  if not healthchecker then
    return nil, "no healthchecker found for " .. tostring(upstream.name)
  end

  local ok, err
  if ip then
    ok, err = healthchecker:set_target_status(ip, port, hostname, is_healthy)
  else
    ok, err = healthchecker:set_all_target_statuses_for_hostname(hostname, port, is_healthy)
  end

  -- adjust API because the healthchecker always returns a second argument
  if ok then
    err = nil
  end

  return ok, err
end


--==============================================================================
-- Health check API
--==============================================================================


--------------------------------------------------------------------------------
-- Subscribe to events produced by health checkers.
-- There is no guarantee that the event reported is different from the
-- previous report (in other words, you may get two "healthy" events in
-- a row for the same target).
-- @param callback Function to be called whenever a target has its
-- status updated. The function should have the following signature:
-- `function(upstream_id, target_ip, target_port, target_hostname, health)`
-- where `upstream_id` is the entity id of the upstream,
-- `target_ip`, `target_port` and `target_hostname` identify the target,
-- and `health` is a string: "healthy", "unhealthy"
-- The return value of the callback function is ignored.
local function subscribe_to_healthcheck_events(callback)
  healthcheck_subscribers[#healthcheck_subscribers + 1] = callback
end


--------------------------------------------------------------------------------
-- Unsubscribe from events produced by health checkers.
-- @param callback Function that was added as the callback.
-- Note that this must be the same closure used for subscribing.
local function unsubscribe_from_healthcheck_events(callback)
  for i, c in ipairs(healthcheck_subscribers) do
    if c == callback then
      table.remove(healthcheck_subscribers, i)
      return
    end
  end
end


local function is_upstream_using_healthcheck(upstream)
  if upstream ~= nil then
    return upstream.healthchecks.active.healthy.interval ~= 0
           or upstream.healthchecks.active.unhealthy.interval ~= 0
           or upstream.healthchecks.passive.unhealthy.tcp_failures ~= 0
           or upstream.healthchecks.passive.unhealthy.timeouts ~= 0
           or upstream.healthchecks.passive.unhealthy.http_failures ~= 0
  end

  return false
end


--------------------------------------------------------------------------------
-- Get healthcheck information for an upstream.
-- @param upstream_id the id of the upstream.
-- @return one of three possible returns:
-- * if healthchecks are enabled, a table mapping keys ("ip:port") to booleans;
-- * if healthchecks are disabled, nil;
-- * in case of errors, nil and an error message.
local function get_upstream_health(upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local using_hc = is_upstream_using_healthcheck(upstream)

  local balancer = balancers[upstream_id]
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker
  if using_hc then
    healthchecker = healthcheckers[balancer]
    if not healthchecker then
      return nil, "healthchecker not found"
    end
  end

  local health_info = {}
  local hosts = balancer.hosts
  for _, host in ipairs(hosts) do
    local key = host.hostname .. ":" .. host.port
    health_info[key] = host:getStatus()
    for _, address in ipairs(health_info[key].addresses) do
      if using_hc then
        address.health = address.healthy and "HEALTHY" or "UNHEALTHY"
      else
        address.health = "HEALTHCHECKS_OFF"
      end
      address.healthy = nil
    end
  end

  return health_info
end


--------------------------------------------------------------------------------
-- Get healthcheck information for a balancer.
-- @param upstream_id the id of the upstream.
-- @return table with balancer health info
local function get_balancer_health(upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    return nil, "upstream not found"
  end

  local balancer = balancers[upstream_id]
  if not balancer then
    return nil, "balancer not found"
  end

  local healthchecker
  local health = "HEALTHCHECKS_OFF"
  if is_upstream_using_healthcheck(upstream) then
    healthchecker = healthcheckers[balancer]
    if not healthchecker then
      return nil, "healthchecker not found"
    end

    local balancer_status = balancer:getStatus()
    health = balancer_status.healthy and "HEALTHY" or "UNHEALTHY"
  end

  return {
    health = health,
    id = upstream_id,
  }
end


--------------------------------------------------------------------------------
-- for unit-testing purposes only
local function _get_healthchecker(balancer)
  return healthcheckers[balancer]
end


--------------------------------------------------------------------------------
-- for unit-testing purposes only
local function _get_target_history(balancer)
  return target_histories[balancer]
end


return {
  init = init,
  execute = execute,
  on_target_event = on_target_event,
  on_upstream_event = on_upstream_event,
  get_upstream_by_name = get_upstream_by_name,
  get_all_upstreams = get_all_upstreams,
  post_health = post_health,
  subscribe_to_healthcheck_events = subscribe_to_healthcheck_events,
  unsubscribe_from_healthcheck_events = unsubscribe_from_healthcheck_events,
  get_upstream_health = get_upstream_health,
  get_upstream_by_id = get_upstream_by_id,
  get_balancer_health = get_balancer_health,

  -- ones below are exported for test purposes only
  _create_balancer = create_balancer,
  _get_balancer = get_balancer,
  _get_healthchecker = _get_healthchecker,
  _get_target_history = _get_target_history,
  _load_upstreams_dict_into_memory = _load_upstreams_dict_into_memory,
  _load_upstream_into_memory = _load_upstream_into_memory,
  _load_targets_into_memory = _load_targets_into_memory,
  _create_hash = create_hash,
}
