local declarative = require("kong.db.declarative")
local kong = kong


return {
  ["/configure"] = {
    POST = function(self, db)
      if kong.db.strategy ~= "off" then
        kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to not use a database"
        })
      end

      local dc = declarative.init(kong.configuration)

      local yaml = self.params.config
      local entities, err = dc:parse_string(yaml, "config.yml", { yaml = true })
      if err then
        return kong.response.exit(400, { error = err })
      end

      declarative.load_into_cache(entities)

      return kong.response.exit(201, entities)
    end,
  },
}
