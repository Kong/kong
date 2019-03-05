local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"


local type = Schema.define {
  type = "string",
  one_of = {
    "page",
    "partial",
    "spec",
  }
}


return {
  name = "files",
  primary_key = { "id" },
  workspaceable = true,
  endpoint_key = "name",

  fields = {
    { id         = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { type       = type },
    { name       = { type = "string", required = true, unique = true } },
    { auth       = { type = "boolean", default = true } },
    { contents   = { type = "string", required = true } },
  }
}
