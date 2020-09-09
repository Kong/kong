local endpoints = require "kong.api.endpoints"


local dp_collection_endpoint = endpoints.get_collection_endpoint(kong.db.clustering_data_planes.schema)


return {
  ["/clustering/data_planes"] = {
    schema = kong.db.clustering_data_planes.schema,
    methods = {
      GET = function(self, dao, helpers)
        if kong.configuration.role ~= "control_plane" then
          return kong.response.exit(400, {
            message = "this endpoint is only available when Kong is " ..
                      "configured to run as Control Plane for the cluster"
          })
        end

        return dp_collection_endpoint(self, dao, helpers)
      end,
    },
  },
}
