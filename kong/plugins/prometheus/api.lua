local prometheus = require "kong.plugins.prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function(self, dao_factory) -- luacheck: ignore 212
      prometheus.collect()
    end,
  },
}
