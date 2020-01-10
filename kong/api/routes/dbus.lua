local databus = require "kong.enterprise_edition.databus"
local dbus_schema = kong.db.dbus.schema
local endpoints = require "kong.api.endpoints"
local kong = kong

local parent_with_ping = function(self, _, _, parent)
  local post_process = function(data)
    if databus.has_ping(data) then
      -- schedule a ping
      databus.queue:add({ callback = databus.ping, data = data })
    end

    return data
  end

  return parent(post_process)
end

return {
  ["/dbus"] = {
    POST = parent_with_ping,
  },
  ["/dbus/:dbus"] = {
    PATCH = parent_with_ping,
  },
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
  ["/dbus/:dbus/ping"] = {
    schema = dbus_schema,
    GET = function(self, db)
      local row, _, err = endpoints.select_entity(self, db, dbus_schema)
      if err then
        return endpoints.handle_error(err)
      elseif row == nil then
        return kong.response.exit(404, { message = "Not found" })
      end

      local ok, err = databus.ping(row)

      if not ok then
        return kong.response.exit(400, { message = err })
      end

      return kong.response.exit(200)
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
