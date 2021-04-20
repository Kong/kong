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


local upstreams = {}
local upstream_by_name = {}

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


function upstreams.get_upstream_by_id(upstream_id)
  local upstream_cache_key = "balancer:upstreams:" .. upstream_id

  return singletons.core_cache:get(upstream_cache_key, nil,
    load_upstream_into_memory, upstream_id)
end


----  ( healthcheckers stuff ? ) ----


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
function upstreams.get_all_upstreams()
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
function upstreams.get_upstream_by_name(upstream_name)
  local ws_id = workspaces.get_workspace_id()
  local key = ws_id .. ":" .. upstream_name

  if upstream_by_name[key] then
    return upstream_by_name[key]
  end

  local upstreams_dict, err = upstreams.get_all_upstreams()
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[key]
  if not upstream_id then
    return false -- no upstream by this name
  end

  local upstream, err = upstreams.get_upstream_by_id(upstream_id)
  if err then
    return nil, err
  end

  upstream_by_name[key] = upstream

  return upstream
end

function upstreams.setUpstream_by_name(upstream)
  local ws_id = workspaces.get_workspace_id()
  upstream_by_name[ws_id .. ":" .. upstream.name] = upstream
end

--==============================================================================
-- Event Callbacks
--==============================================================================


local upstream_events_queue = {}

local function do_upstream_event(operation, upstream_data)
  local upstream_id = upstream_data.id
  local upstream_name = upstream_data.name
  local ws_id = workspaces.get_workspace_id()
  local by_name_key = ws_id .. ":" .. upstream_name

  if operation == "create" then
    local upstream, err = upstreams.get_upstream_by_id(upstream_id)
    if err then
      return nil, err
    end

    if not upstream then
      log(ERR, "upstream not found for ", upstream_id)
      return
    end

    local _, err = create_balancer(upstream)
    if err then
      log(CRIT, "failed creating balancer for ", upstream_name, ": ", err)
    end

  elseif operation == "delete" or operation == "update" then
    local target_cache_key = "balancer:targets:"   .. upstream_id
    if singletons.db.strategy ~= "off" then
      singletons.core_cache:invalidate_local(target_cache_key)
    end

    local balancer = balancers[upstream_id]
    if balancer then
      stop_healthchecker(balancer)
    end

    if operation == "delete" then
      set_balancer(upstream_id, nil)
      upstream_by_name[by_name_key] = nil

    else
      local upstream = upstreams.get_upstream_by_id(upstream_id)

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


local function set_upstream_events_queue(operation, upstream_data)
  -- insert the new event into the end of the queue
  upstream_events_queue[#upstream_events_queue + 1] = {
    operation = operation,
    upstream_data = upstream_data,
  }
end


local function get_upstream_events_queue()
  -- is this copy really needed
  return utils.deep_copy(upstream_events_queue)
end


function upstreams.update_balancer_state(premature)
  if premature then
    return
  end

  local events_queue = get_upstream_events_queue()

  for i, v in ipairs(events_queue) do
    -- handle the oldest (first) event from the queue
    local _, err = do_upstream_event(v.operation, v.upstream_data, v.workspaces)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
      return
    end

    -- if no err, remove the upstream event from the queue
    table_remove(upstream_events_queue, i)
  end

  local frequency = kong.configuration.worker_state_update_frequency or 1
  local _, err = timer_at(frequency, upstreams.update_balancer_state)
  if err then
    log(CRIT, "unable to reschedule update proxy state timer: ", err)
  end

end




--------------------------------------------------------------------------------
-- Called on any changes to an upstream.
-- @param operation "create", "update" or "delete"
-- @param upstream_data table with `id` and `name` fields
function upstreams.on_upstream_event(operation, upstream_data)
  if kong.configuration.worker_consistency == "strict" then
    local _, err = do_upstream_event(operation, upstream_data)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
    end
  else
    set_upstream_events_queue(operation, upstream_data)
  end
end


return upstreams
