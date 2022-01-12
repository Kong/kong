--- Cluster-level utilities.
--
-- @module kong.cluster


local kong = kong
local CLUSTER_ID_PARAM_KEY = require("kong.constants").CLUSTER_ID_PARAM_KEY


local function fetch_cluster_id()
  local res, err = kong.db.parameters:select({ key = CLUSTER_ID_PARAM_KEY, })
  if not res then
    return nil, err
  end

  return res.value
end


local function new(self)
  local _CLUSTER = {}


  ---
  -- Returns the unique ID for this Kong cluster. If Kong
  -- is running in DB-less mode without a cluster ID explicitly defined,
  -- then this method returns `nil`.
  --
  -- For hybrid mode, all control planes and data planes belonging to the same
  -- cluster return the same cluster ID. For traditional database-based
  -- deployments, all Kong nodes pointing to the same database also return
  -- the same cluster ID.
  --
  -- @function kong.cluster.get_id
  -- @treturn string|nil The v4 UUID used by this cluster as its ID.
  -- @treturn string|nil An error message.
  -- @usage
  -- local id, err = kong.cluster.get_id()
  -- if err then
  --   -- handle error
  -- end
  --
  -- if not id then
  --   -- no cluster ID is available
  -- end
  --
  -- -- use id here
  function _CLUSTER.get_id()
    return kong.core_cache:get(CLUSTER_ID_PARAM_KEY, nil, fetch_cluster_id)
  end


  return _CLUSTER
end


return {
  new = new,
}
