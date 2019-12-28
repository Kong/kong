local typedefs = require "kong.db.schema.typedefs"
local databus = require "kong.enterprise_edition.databus"

local fmt = string.format
local ngx_null = ngx.null

return {
  name         = "dbus",
  primary_key  = { "id" },
  endpoint_key = "id",
  subschema_key = "handler",
  -- XXX: foreign key like plugins:
  -- routes / services / consumers
  -- let's see if it works
  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { source         = { type = "string", required = true } },
    { event          = { type = "string" } },
    { handler        = { type = "string", required = true,
                         default = "webhook" } },
    { config         = { type = "record", required = true, abstract = true } },
  },
  -- XXX if no entity check, then always have an empty entity_checks
  -- force read before write so we always have old_entity on the events
  -- any other way of accomplishing the same thing?
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "source", "event" },
      -- Force source and event to exist. This is nice, but at the same time
      -- it can be limiting, since lambdas would not be able to register
      -- events. ?
      fn = function(entity)
        local events = databus.list()
        local source = entity.source
        local event = entity.event ~= ngx_null and entity.event or nil
        if not events[source] then
          return nil, fmt("source '%s' is not registered", source)
        end

        if event and not events[source][event] then
          return nil, fmt("source '%s' has no '%s' event", source, event)
        end

        return true
      end
    } }
  }
}
