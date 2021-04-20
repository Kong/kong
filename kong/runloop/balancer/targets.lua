---
--- manages a cache of targets belonging to an upstream.
--- each one represents a hostname with a weight,
--- health status and a list of addresses.
---
--- maybe it could eventually be merged into the DAO object?
---


------------------------------------------------------------------------------
-- Loads the targets from the DB.
-- @param upstream_id Upstream uuid for which to load the target
-- @return The target array, with target entity tables.
local function load_targets_into_memory(upstream_id)

  local targets, err, err_t =
  singletons.db.targets:select_by_upstream_raw({ id = upstream_id }, GLOBAL_QUERY_OPTS)

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
_load_targets_into_memory = load_targets_into_memory


------------------------------------------------------------------------------
-- Fetch targets, from cache or the DB.
-- @param upstream The upstream entity object
-- @return The targets array, with target entity tables.
local function fetch_targets(upstream)
  local targets_cache_key = "balancer:targets:" .. upstream.id

  return singletons.core_cache:get(targets_cache_key, nil,
    load_targets_into_memory, upstream.id)
end


--------------------------------------------------------------------------------
-- Add targets to the balancer.
-- @param balancer balancer object
-- @param targets list of targets to be applied
local function add_targets(balancer, targets)

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
local function on_target_event(operation, target)
  local upstream_id = target.upstream.id
  local upstream_name = target.upstream.name

  log(DEBUG, "target ", operation, " for upstream ", upstream_id,
    upstream_name and " (" .. upstream_name ..")" or "")

  singletons.core_cache:invalidate_local("balancer:targets:" .. upstream_id)

  local upstream = get_upstream_by_id(upstream_id)
  if not upstream then
    log(ERR, "target ", operation, ": upstream not found for ", upstream_id,
      upstream_name and " (" .. upstream_name ..")" or "")
    return
  end

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
