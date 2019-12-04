local typedefs = require "kong.db.schema.typedefs"

local databus = require "kong.enterprise_edition.databus"

-- need crud event to re-add a new event

return {
  name         = "dbus",
  primary_key  = { "id" },
  endpoint_key = "id",
  -- foreign key like plugins:
  -- routes / services / consumers
  -- let's see if it works
  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { source         = { type = "string" } },
    { event          = { type = "string" } },
    { handler        = { type = "string" } },
    -- Make this config abstract. It fails, but I suspect a bug
    -- ie { type = "record", abstract = true } },
    { config         = databus.schema.webhook },
  }
}
