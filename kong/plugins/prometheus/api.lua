local Schema = require("kong.db.schema")
local prometheus = require "kong.plugins.prometheus.exporter"

-- schemas are used to parse parameters, for example: all params in a
-- form-url-encoded field arrive to the server as strings. But if the provided
-- schema has a field called `timeout` of type `number` then it will be transformed
-- into a number before being passed down to the functions below.
--
-- On this particular case the Prometheus lib uses no schemas and the /metrics
-- path accepts no parameters, but we still need to supply a schema in order to use the
-- "new-db-style" admin API. So we generate an empty one on the fly.
local empty_schema = Schema.new({ fields = {} })

return {

  ["/metrics"] = {
    schema = empty_schema,
    methods = {
      GET = function()
        prometheus.collect()
      end,
    },
  },
}
