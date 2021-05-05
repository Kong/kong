---
--- manages a cache of targets belonging to an upstream.
--- each one represents a hostname with a weight,
--- health status and a list of addresses.
---
--- maybe it could eventually be merged into the DAO object?
---

local singletons = require "kong.singletons"

local dns_client = require "kong.runloop.balancer.dns_client"
local upstreams = require "kong.runloop.balancer.upstreams"
local balancers   -- require at init time to avoid dependency loop

local ngx = ngx
local log = ngx.log
local null = ngx.null
local match = string.match
local ipairs = ipairs
local tonumber = tonumber
--local assert = assert


local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


local targets_M = {}


function targets_M.init()
  balancers = require "kong.runloop.balancer.balancers"
  dns_client.init()
end


------------------------------------------------------------------------------
-- Loads the targets from the DB.
-- @param upstream_id Upstream uuid for which to load the target
-- @return The target array, with target entity tables.
local function load_targets_into_memory(upstream_id)

  local targets, err, err_t = singletons.db.targets:select_by_upstream_raw(
      { id = upstream_id }, GLOBAL_QUERY_OPTS)

  if not targets then
    return nil, err, err_t
  end

  -- perform some raw data updates
  for _, target in ipairs(targets) do
    -- split `target` field into `name` and `port`
    local port
    target.name, port = match(target.target, "^(.-):(%d+)$")
    target.port = tonumber(port)
    target.addresses = {}
  end

  return targets
end
--_load_targets_into_memory = load_targets_into_memory


------------------------------------------------------------------------------
-- Fetch targets, from cache or the DB.
-- @param upstream The upstream entity object
-- @return The targets array, with target entity tables.
function targets_M.fetch_targets(upstream)
  local targets_cache_key = "balancer:targets:" .. upstream.id

  return singletons.core_cache:get(
      targets_cache_key, nil,
      load_targets_into_memory, upstream.id)
end


-- resolve a target, filling the list of addresses
local function resolve_target(balancer, target)
  dns_client.queryDns({
    hostname = target.name,
    port = target.port,
    nodeWeight = target.weight,
    target = target,
    balancer = balancer,
  })
end

function targets_M.resolve_targets(balancer, targets_list)
  for _, target in ipairs(targets_list) do
    local resolved, err = resolve_target(balancer, target)
    if not resolved then
      return nil, err
    end

  end

  return targets_list
end

--==============================================================================
-- Event Callbacks
--==============================================================================



--------------------------------------------------------------------------------
-- Called on any changes to a target.
-- @param operation "create", "update" or "delete"
-- @param target Target table with `upstream.id` field
function targets_M.on_target_event(operation, target)
  local upstream_id = target.upstream.id
  local upstream_name = target.upstream.name

  log(DEBUG, "target ", operation, " for upstream ", upstream_id,
    upstream_name and " (" .. upstream_name ..")" or "")

  singletons.core_cache:invalidate_local("balancer:targets:" .. upstream_id)

  local upstream = upstreams.get_upstream_by_id(upstream_id)
  if not upstream then
    log(ERR, "target ", operation, ": upstream not found for ", upstream_id,
      upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

-- move this to upstreams?
  local balancer = balancers.get_balancer_by_id(upstream_id)
  if not balancer then
    log(ERR, "target ", operation, ": balancer not found for ", upstream_id,
      upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

  local new_balancer, err = balancers.create_balancer(upstream, true)
  if not new_balancer then
    return nil, err
  end

  return true
end

return targets_M
