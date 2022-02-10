local declarative = require("kong.db.declarative")

local kong = kong

return {
  ["/status/config"] = {
    GET = function(self, dao, helpers)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(200)
      end
    -- unintuitively, "true" is unitialized. we do always initialize the shdict key
    -- after a config loads, this returns the hash string
    if not declarative.has_config() then
      return kong.response.exit(503)
    end

    return kong.response.exit(200)
    end
  },
}
