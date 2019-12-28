local databus = require "kong.enterprise_edition.databus"
local kong = kong

return {
  ["/dbus/sources"] = {
    GET = function(self, db, helpers, parent)
      return kong.response.exit(200, { data = databus.list() })
    end
  },
  ["/dbus/sources/:source"] = {
    GET = function(self, db, helpers, parent)
      local source = self.params.source
      local sources = databus.list()

      if not sources[source] then
        return kong.response.exit(404, { message = "Not Found" })
      end

      return kong.response.exit(200, { data = sources[source] })
    end
  },
}
