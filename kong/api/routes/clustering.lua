local endpoints = require "kong.api.endpoints"


local kong = kong


local dp_collection_endpoint = endpoints.get_collection_endpoint(kong.db.clustering_data_planes.schema)


return {
  ["/clustering/data-planes"] = {
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

  ["/clustering/status"] = {
    schema = kong.db.clustering_data_planes.schema,
    methods = {
      GET = function(self, db, helpers)
        if kong.configuration.role ~= "control_plane" then
          return kong.response.exit(400, {
            message = "this endpoint is only available when Kong is " ..
                      "configured to run as Control Plane for the cluster"
          })
        end

        local data = {}

        for row, err in kong.db.clustering_data_planes:each() do
          if err then
            kong.log.err(err)
            return kong.response.exit(500, { message = "An unexpected error happened" })
          end

          local id = row.id
          row.id = nil

          data[id] = row
        end

        return kong.response.exit(200, data, {
          ["Deprecation"] = "true" -- see: https://tools.ietf.org/html/draft-dalal-deprecation-header-03
        })
      end,
    },
  },
}
