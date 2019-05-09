local declarative = require("kong.db.declarative")
local concurrency = require("kong.concurrency")
local reports = require("kong.reports")
local errors = require("kong.db.errors")
local kong = kong
local dc = declarative.new_config(kong.configuration)


-- Do not accept Lua configurations from the Admin API
-- because it is Turing-complete.
local accept = {
  yaml = true,
  json = true,
}

local _reports = {
  decl_fmt_version = false,
}


return {
  ["/config"] = {
    POST = function(self, db)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to not use a database"
        })
      end

      local entities, err_or_ver, err_t
      if self.params._format_version then
        entities, err_or_ver, err_t = dc:parse_table(self.params)
      else
        local config = self.params.config
        entities, err_or_ver, err_t = dc:parse_string(config, nil, accept)
      end

      if not entities then
        return kong.response.exit(400, errors:declarative_config(err_t))
      end

      local ok, err = concurrency.with_worker_mutex({ name = "dbless-worker" }, function()
        return declarative.load_into_cache_with_events(entities)
      end)

      if err == "no memory" then
        kong.log.err("not enough cache space for declarative config")
        return kong.response.exit(413, {
          message = "Configuration does not fit in Kong cache"
        })
      end

      if not ok then
        kong.log.err("failed loading declarative config into cache: ", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      _reports.decl_fmt_version = err_or_ver
      reports.send("dbless-reconfigure", _reports)

      return kong.response.exit(201, entities)
    end,
  },
}
