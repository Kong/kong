local declarative = require("kong.db.declarative")

local kong = kong

return {
  ["/status/config"] = {
    GET = function(self, dao, helpers)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(200)
      end
    local ready, hash = declarative.has_config()
    if not ready then
      return kong.response.exit(503, hash)
    end

    return kong.response.exit(200, hash)
    end
  },
}
