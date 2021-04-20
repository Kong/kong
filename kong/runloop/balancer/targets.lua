---
--- manages a cache of targets belonging to an upstream.
--- each one represents a hostname with a weight,
--- health status and a list of addresses.
---
--- maybe it could eventually be merged into the DAO object?
---

local singletons = require "kong.singletons"

-- due to startup/require order, cannot use the ones from 'kong' here
local dns_client = require "resty.dns.client"

local upstreams = require "kong.runloop.balancer.upstreams"

local toip = dns_client.toip
local ngx = ngx
local log = ngx.log
local sleep = ngx.sleep
local null = ngx.null
local min = math.min
local max = math.max
local type = type
local sub = string.sub
local find = string.find
local match = string.match
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local assert = assert
local table = table
local table_concat = table.concat
local table_remove = table.remove
local timer_at = ngx.timer.at
local run_hook = hooks.run_hook
local var = ngx.var
local get_phase = ngx.get_phase


local CRIT = ngx.CRIT
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local EMPTY_T = pl_tablex.readonly {}

local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


local targets_M = {}

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


--------------------------------------------------------------------------------
-- Add targets to the balancer.
-- @param balancer balancer object
-- @param targets list of targets to be applied
function targets_M.add_targets(balancer, targets)

  for _, target in ipairs(targets) do
    if target.weight > 0 then
      assert(balancer:addHost(target.name, target.port, target.weight))
    else
      assert(balancer:removeHost(target.name, target.port))
    end

  end
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
  local balancer = balancers[upstream_id]
  if not balancer then
    log(ERR, "target ", operation, ": balancer not found for ", upstream_id,
      upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

  local new_balancer, err = create_balancer(upstream, true)
  if not new_balancer then
    return nil, err
  end

  return true
end


return targets_M
