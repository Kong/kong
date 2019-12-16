local typedefs = require "kong.db.schema.typedefs"

local kong = kong

local _M = {}

local events = {}

-- Not sure if this is good enough. Holds references to callbacks by id so
-- we can properly unregister worker events
local references = {}

_M.publish = function(source, event, help)
  if not events[source] then events[source] = {} end
  events[source][#events[source] + 1] = { event, help }
end

_M.register = function(entity)
  local callback = _M.callback(entity)
  local source = entity.source
  local event = entity.event

  references[entity.id] = callback

  return kong.worker_events.register(callback, "dbus:" .. source, event)
end

_M.unregister = function(entity)
  local callback = references[entity.id]
  local source = entity.source
  local event = entity.event

  return kong.worker_events.unregister(callback, "dbus:" .. source, event)
end

_M.emit = function(source, event, data)
  return kong.worker_events.post_local("dbus:" .. source, event, data)
end

_M.list = function()
  return events
end

_M.callback = function(entity)
  -- XXX hardcoded to webhook
  return _M.webhook(entity.config)
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
