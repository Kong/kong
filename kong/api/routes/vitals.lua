local singletons = require "kong.singletons"

if not singletons.configuration.vitals then
  return {}
end

return {
  ["/vitals/"] = {
    GET = function(self, dao, helpers)
      local current_stats = singletons.vitals:get_stats("seconds")


      return helpers.responses.send_HTTP_OK({ stats = current_stats })
    end

  },
  ["/vitals/minutes"] = {
    GET = function(self, dao, helpers)
      local current_minute_stats = singletons.vitals:get_stats("minutes")


      return helpers.responses.send_HTTP_OK({ stats = current_minute_stats })
    end

  }
}
