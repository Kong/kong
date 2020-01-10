local databus = require "kong.enterprise_edition.databus"
local dbus_schema = kong.db.dbus.schema
local endpoints = require "kong.api.endpoints"
local kong = kong

return {
  ["/dbus/:dbus/test"] = {
    schema = dbus_schema,
    POST = function(self, db)
      local row, _, err = endpoints.select_entity(self, db, dbus_schema)
      if err then
        return endpoints.handle_error(err)
      elseif row == nil then
        return kong.response.exit(404, { message = "Not found" })
      end

      local ok, data, err = databus.test(row, self.args.post)

      if not ok then
        return kong.response.exit(500, { message = "An unexpected error ocurred", err = err })
      end

      return kong.response.exit(200, { data = data })
    end,
  },
  ["/dbus/sources"] = {
    GET = function(self, db)
      return kong.response.exit(200, { data = databus.list() })
    end
  },
  ["/dbus/sources/:source"] = {
    GET = function(self, db)
      local source = self.params.source
      local sources = databus.list()

      if not sources[source] then
        return kong.response.exit(404, { message = "Not Found" })
      end

      return kong.response.exit(200, { data = sources[source] })
    end
  },
}
