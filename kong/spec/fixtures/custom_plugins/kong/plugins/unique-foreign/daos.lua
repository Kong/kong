local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "unique_foreigns",
    primary_key = { "id" },
    admin_api_name = "unique-foreigns",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string" }, },
    },
  },
  {
    name = "unique_references",
    primary_key = { "id" },
    admin_api_name = "unique-references",
    fields = {
      { id = typedefs.uuid },
      { note = { type = "string" }, },
      { unique_foreign = { type = "foreign", reference = "unique_foreigns", on_delete = "cascade", unique = true }, },
    },
  },
}
