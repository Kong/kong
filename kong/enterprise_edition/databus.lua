local typedefs = require "kong.db.schema.typedefs"

local kong = kong

local _M = {}

local events = {}

_M.publish = function(source, event, help)
  if not events[source] then events[source] = {} end
  events[source][#events[source] + 1] = { event, help }
end

_M.register = function(callback, source, event)
  return kong.worker_events.register(callback, "dbus:"..source, event)
end

_M.emit = function(source, event, data)
  return kong.worker_events.post_local("dbus:"..source, event, data)
end

_M.list = function()
  return events
end

_M.schema = {
  webhook = {
    type = "record",
    fields = {
      { host = typedefs.host },
      { port = typedefs.port },
      { method = typedefs.http_method },
      { protocol = typedefs.protocol { required = true, default = "http" } },
    },
  },
  log = {
    type = "record",
    fields = {},
  }
}

_M.webhook = function(config)
  return function(data, event, source, pid)
    ngx.log(ngx.ERR, [[self:]], require("inspect")({config, data, event, source, pid}))
  end
end

return _M
