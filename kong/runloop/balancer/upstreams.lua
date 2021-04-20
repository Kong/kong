---
--- manages a cache of upstream objects
--- and the relationship with healthcheckers and balancers
---
--- maybe it could eventually be merged into the DAO object?
---
---



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
_load_upstream_into_memory = load_upstream_into_memory


local function get_upstream_by_id(upstream_id)
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
_load_upstreams_dict_into_memory = load_upstreams_dict_into_memory


local opts = { neg_ttl = 10 }


------------------------------------------------------------------------------
-- Implements a simple dictionary with all upstream-ids indexed
-- by their name.
-- @return The upstreams dictionary (a map with upstream names as string keys
-- and upstream entity tables as values), or nil+error
local function get_all_upstreams()
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
local function get_upstream_by_name(upstream_name)
  local ws_id = workspaces.get_workspace_id()
  local key = ws_id .. ":" .. upstream_name

  if upstream_by_name[key] then
    return upstream_by_name[key]
  end

  local upstreams_dict, err = get_all_upstreams()
  if err then
    return nil, err
  end

  local upstream_id = upstreams_dict[key]
  if not upstream_id then
    return false -- no upstream by this name
  end

  local upstream, err = get_upstream_by_id(upstream_id)
  if err then
    return nil, err
  end

  upstream_by_name[key] = upstream

  return upstream
end



--==============================================================================
-- Event Callbacks
--==============================================================================




local function do_upstream_event(operation, upstream_data)
  local upstream_id = upstream_data.id
  local upstream_name = upstream_data.name
  local ws_id = workspaces.get_workspace_id()
  local by_name_key = ws_id .. ":" .. upstream_name

  if operation == "create" then
    local upstream, err = get_upstream_by_id(upstream_id)
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
  if kong.configuration.worker_consistency == "strict" then
    local _, err = do_upstream_event(operation, upstream_data)
    if err then
      log(CRIT, "failed handling upstream event: ", err)
    end
  else
    set_upstream_events_queue(operation, upstream_data)
  end
end
