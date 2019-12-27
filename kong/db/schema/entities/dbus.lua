local typedefs = require "kong.db.schema.typedefs"

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
  -- XXX force read before write so we always have old_entity on the events
  -- any other way of accomplishing the same thing?
  entity_checks = {},
}
