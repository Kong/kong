local declarative = require("kong.db.declarative")
local reports = require("kong.reports")
local errors = require("kong.db.errors")


local kong = kong
local ngx = ngx
local type = type
local table = table
local tostring = tostring


local _reports = {
  decl_fmt_version = false,
}


local function reports_timer(premature)
  if premature then
    return
  end

  reports.send("dbless-reconfigure", _reports)
end


local function truthy(val)
  if type(val) == "string" then
    val = val:lower()
  end

  return val == true
      or val == 1
      or val == "true"
      or val == "1"
      or val == "on"
      or val == "yes"
end


local function hydrate_config_from_request(params, dc)
  if params._format_version then
    return params
  end

  local config = params.config

  if not config then
    local body = kong.request.get_raw_body()
    if type(body) == "string" and #body > 0 then
      config = body

    else
      return kong.response.exit(400, {
        message = "expected a declarative configuration"
      })
    end
  end

  local dc_table, _, err_t, new_hash = dc:unserialize(config)
  if not dc_table then
    return kong.response.exit(400, errors:declarative_config(err_t))
  end

  return dc_table, new_hash
end


local function parse_config_post_opts(params)
  local flatten_errors = truthy(params.flatten_errors)
  params.flatten_errors = nil

  -- XXX: this code is much older than the `flatten_errors` flag and therefore
  -- does not use the same `truthy()` helper, for backwards compatibility
  local check_hash = tostring(params.check_hash) == "1"
  params.check_hash = nil

  return {
    flatten_errors = flatten_errors,
    check_hash = check_hash,
  }
end


return {
  ["/config"] = {
    GET = function(self, db)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to not use a database"
        })
      end

      local file = {
        buffer = {},
        write = function(self, str)
          self.buffer[#self.buffer + 1] = str
        end,
      }

      local ok, err = declarative.export_from_db(file)
      if not ok then
        kong.log.err("failed exporting config from cache: ", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      return kong.response.exit(200, { config = table.concat(file.buffer) })
    end,
    POST = function(self, db)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to not use a database"
        })
      end

      local opts = parse_config_post_opts(self.params)

      local old_hash = opts.check_hash and declarative.get_current_hash()

      local dc = kong.db.declarative_config
      if not dc then
        kong.log.crit("received POST request to /config endpoint, but ",
                      "kong.db.declarative_config was not initialized")
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      local dc_table, new_hash = hydrate_config_from_request(self.params, dc)

      if opts.check_hash and new_hash and old_hash == new_hash then
        return kong.response.exit(304)
      end

      local entities, _, err_t, meta
      entities, _, err_t, meta, new_hash = dc:parse_table(dc_table, new_hash)

      if not entities then
        local res

        if opts.flatten_errors and dc_table then
          res = errors:declarative_config_flattened(err_t, dc_table)
        else
          res = errors:declarative_config(err_t)
        end

        return kong.response.exit(400, res)
      end

      local ok, err, ttl = declarative.load_into_cache_with_events(entities, meta, new_hash)

      if not ok then
        if err == "busy" or err == "locked" then
          return kong.response.exit(429, {
            message = "Currently loading previous configuration"
          }, { ["Retry-After"] = ttl })
        end

        if err == "timeout" then
          return kong.response.exit(504, {
            message = "Timed out while loading configuration"
          })
        end

        if err == "exiting" then
          return kong.response.exit(503, {
            message = "Kong currently exiting"
          })
        end

        if err == "map full" then
          kong.log.err("not enough space for declarative config")
          return kong.response.exit(413, {
            message = "Configuration does not fit in LMDB database, " ..
                      "consider raising the \"lmdb_map_size\" config for Kong"
          })
        end

        kong.log.err("failed loading declarative config into cache: ", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      _reports.decl_fmt_version = meta._format_version

      ngx.timer.at(0, reports_timer)

      declarative.sanitize_output(entities)
      return kong.response.exit(201, entities)
    end,
  },
}
