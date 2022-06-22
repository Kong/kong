--- Cluster-level utilities.
--
-- @module kong.cluster


local kong = kong
local CLUSTER_ID_PARAM_KEY = require("kong.constants").CLUSTER_ID_PARAM_KEY
local clustering_services = require("kong.clustering.services")
local services_register = clustering_services.register
local get_services = clustering_services.get_services


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

  _CLUSTER.services = {
    ---
    -- Register a service for Kong cluster.
    --
    -- @function kong.cluster.services.register
    -- @tparam name string name of the serivce
    -- @tparam versions table array of versions of the serivce, echo with fields like: { version = "v1", description = "example service" }
    -- @tparam service_init_dp function|nil callback to register wRPC services for dp if needed
    -- @tparam service_init_cp function|nil callback to register wRPC services for cp if needed
    -- @return nil
    -- @usage
    -- local ok, err = pcall(
    --   kong.cluster.service.register, "example_service",
    --   {
    --     { version = "v1", description = "example service" },
    --   },
    --   init_dp, init_cp)
    -- if not ok then
    --   -- handle error
    -- end
    -- -- use id here
    register = services_register,

    
    ---
    -- Get all services' info for Kong cluster.
    --
    -- @function kong.cluster.services.get_services
    -- @return table
    -- @usage
    -- local services = kong.cluster.services.get_services()
    -- for name, info in pairs(services) do
    --   -- do what you want with services info
    -- end
    get_services = get_services,
  }

  return _CLUSTER
end


return {
  new = new,
}
