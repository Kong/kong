local typedefs = require "kong.db.schema.typedefs"
local event_hooks = require "kong.enterprise_edition.event_hooks"

local fmt = string.format
local ngx_null = ngx.null

return {
  name         = "event_hooks",
  primary_key  = { "id" },
  endpoint_key = "id",
  subschema_key = "handler",
  -- disable auto admin API to manually map /event-hooks routes
  generate_admin_api = false,
  -- XXX: foreign key support like plugins:
  -- routes / services / consumers ?
  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { source         = { type = "string", required = true } },
    { event          = { type = "string" } },
    { on_change      = { type = "boolean" } },
    { snooze         = { type = "integer" } },
    { handler        = { type = "string", required = true,
                         default = "webhook" } },
    { config         = { type = "record", required = true, abstract = true } },
  },
  -- This entity check makes sure the source and the event exist, assuming
  -- they have been published using event_hooks.publish.
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "source", "event" },
      -- Force source and event to exist. This is nice, but at the same time
      -- it can be limiting, since lambdas would not be able to register
      -- events. ?
      fn = function(entity)
        local events = event_hooks.list()
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
