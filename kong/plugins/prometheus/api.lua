local prometheus = require "kong.plugins.prometheus.exporter"

local consumers_schema = kong.db.consumers.schema

return {

  ["/metrics"] = {
    schema = consumers_schema, -- not used, could be any schema
    methods = {
      GET = function()
        prometheus.collect()
      end,
    },
  },
}
