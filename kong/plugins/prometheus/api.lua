local prometheus = require "kong.plugins.prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function(self, dao_factory)
      prometheus.collect()
    end,
  },
}
