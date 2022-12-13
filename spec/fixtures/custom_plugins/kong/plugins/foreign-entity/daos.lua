local typedefs = require "kong.db.schema.typedefs"


return {
  {
    name = "foreign_entities",
    primary_key = { "id" },
    endpoint_key = "name",
    admin_api_name = "foreign-entities",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string", unique = true } },
      { same = typedefs.uuid },
    },
  },
  {
    name = "foreign_references",
    primary_key = { "id" },
    endpoint_key = "name",
    admin_api_name = "foreign-references",
    fields = {
      { id = typedefs.uuid },
      { name = { type = "string", unique = true } },
      { same = { type = "foreign", reference = "foreign_entities", on_delete = "cascade" } },
    },
  },
}
