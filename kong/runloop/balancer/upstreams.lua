---
--- manages a cache of upstream objects
--- and the relationship with healthcheckers and balancers
---
--- maybe it could eventually be merged into the DAO object?
---
---
---
local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local balancers
local healthcheckers

local ngx = ngx
local log = ngx.log
local null = ngx.null
local table_remove = table.remove
local timer_at = ngx.timer.at


local CRIT = ngx.CRIT
local ERR = ngx.ERR

local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


local upstreams_M = {}
local upstream_by_name = {}


function upstreams_M.init()
  balancers = require "kong.runloop.balancer.balancers"
  healthcheckers = require "kong.runloop.balancer.healthcheckers"
end




-- Caching logic
--
-- We retain 3 entities in cache:
--
-- 1) `"balancer:upstreams"` - a list of upstreams
--    to be invalidated on any upstream change
-- 2) `"balancer:upstreams:" .. id` - individual upstreams
--    to be invalidated on individual basis
-- 3) `"balancer:targets:" .. id`
--    target for an upstream along with the upstream it belongs to
--
-- Distinction between 1 and 2 makes it possible to invalidate individual
-- upstreams, instead of all at once forcing to rebuild all balancers



------------------------------------------------------------------------------
-- Loads a single upstream entity.
-- @param upstream_id string
-- @return the upstream table, or nil+error
local function load_upstream_into_memory(upstream_id)
  local upstream, err = singletons.db.upstreams:select({id = upstream_id}, GLOBAL_QUERY_OPTS)
  if not upstream then
    return nil, err
  end

  return upstream
end
--_load_upstream_into_memory = load_upstream_into_memory


function upstreams_M.get_upstream_by_id(upstream_id)
  local upstream_cache_key = "balancer:upstreams:" .. upstream_id

  return singletons.core_cache:get(upstream_cache_key, nil,
    load_upstream_into_memory, upstream_id)
end


------------------------------------------------------------------------------

local function load_upstreams_dict_into_memory()
  local upstreams_dict = {}
  local found = nil

  -- build a dictionary, indexed by the upstream name
  for up, err in singletons.db.upstreams:each(nil, GLOBAL_QUERY_OPTS) do
    if err then
      log(CRIT, "could not obtain list of upstreams: ", err)
      return nil
    end

    upstreams_dict[up.ws_id .. ":" .. up.name] = up.id
    found = true
  end

  return found and upstreams_dict
end
--_load_upstreams_dict_into_memory = load_upstreams_dict_into_memory


local opts = { neg_ttl = 10 }

------------------------------------------------------------------------------
-- Implements a simple dictionary with all upstream-ids indexed
-- by their name.
-- @return The upstreams dictionary (a map with upstream names as string keys
-- and upstream entity tables as values), or nil+error
function upstreams_M.get_all_upstreams()
  local upstreams_dict, err = singletons.core_cache:get("balancer:upstreams", opts,
                                                        load_upstreams_dict_into_memory)
  if err then
    return nil, err
  end

  return upstreams_dict or {}
end

------------------------------------------------------------------------------
-- Finds and returns an upstream entity. This function covers
-- caching, invalidation, db access, et al.
-- @param upstream_name string.
-- @return upstream table, or `false` if not found, or nil+error
function upstreams_M.get_upstream_by_name(upstream_name)
  local ws_id = workspaces.get_workspace_id()
  local key = ws_id .. ":" .. upstream_name

  if upstream_by_name[key] then
    return upstream_by_name[key]
  end

  local upstreams_dict, err = upstreams_M.get_all_upstreams()
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[key]
  if not upstream_id then
    return false -- no upstream by this name
  end

  local upstream, err = upstreams_M.get_upstream_by_id(upstream_id)
  if err then
    return nil, err
  end

  upstream_by_name[key] = upstream

  return upstream
end

function upstreams_M.setUpstream_by_name(upstream)
  local ws_id = upstream.ws_id or workspaces.get_workspace_id()
  upstream_by_name[ws_id .. ":" .. upstream.name] = upstream
end

--==============================================================================
-- Event Callbacks
--==============================================================================


local upstream_events_queue = {}

local function do_upstream_event(operation, upstream_data)
  local upstream_id = upstream_data.id
  local upstream_name = upstream_data.name
  local ws_id = upstream_data.ws_id or workspaces.get_workspace_id()
  local by_name_key = ws_id .. ":" .. upstream_name

  if operation == "create" then
    local upstream, err = upstreams_M.get_upstream_by_id(upstream_id)
    if err then
      return nil, err
    end

    if not upstream then
      log(ERR, "upstream not found for ", upstream_id)
      return
    end

    local _, err = balancers.create_balancer(upstream)
    if err then
      log(CRIT, "failed creating balancer for ", upstream_name, ": ", err)
    end

  elseif operation == "delete" or operation == "update" then
    local target_cache_key = "balancer:targets:" .. upstream_id
    if singletons.db.strategy ~= "off" then
      singletons.core_cache:invalidate_local(target_cache_key)
    end

    local balancer = balancers.get_balancer_by_id(upstream_id)
    if balancer then
      healthcheckers.stop_healthchecker(balancer)
    end

    if operation == "delete" then
      balancers.set_balancer(upstream_id, nil)
      upstream_by_name[by_name_key] = nil

    else
      local upstream = upstreams_M.get_upstream_by_id(upstream_id)
      if not upstream then
        log(ERR, "upstream not found for ", upstream_id)
        return
      end

      local _, err = balancers.create_balancer(upstream, true)
      if err then
        log(ERR, "failed recreating balancer for ", upstream_name, ": ", err)
      end
    end

  end

end


local function set_upstream_events_queue(operation, upstream_data)
  -- insert the new event into the end of the queue
  upstream_events_queue[#upstream_events_queue + 1] = {
    operation = operation,
    upstream_data = upstream_data,
  }
end


function upstreams_M.update_balancer_state(premature)
  if premature then
    return
  end


  while upstream_events_queue[1] do
    local event  = upstream_events_queue[1]
    local _, err = do_upstream_event(event.operation, event.upstream_data)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
      return
    end

    table_remove(upstream_events_queue, 1)
  end

  local frequency = kong.configuration.worker_state_update_frequency or 1
  local _, err = timer_at(frequency, upstreams_M.update_balancer_state)
  if err then
    log(CRIT, "unable to reschedule update proxy state timer: ", err)
  end

end




--------------------------------------------------------------------------------
-- Called on any changes to an upstream.
-- @param operation "create", "update" or "delete"
-- @param upstream_data table with `id` and `name` fields
function upstreams_M.on_upstream_event(operation, upstream_data)
  if kong.configuration.worker_consistency == "strict" then
    local _, err = do_upstream_event(operation, upstream_data)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
    end
  else
    set_upstream_events_queue(operation, upstream_data)
  end
end

return upstreams_M
