return {
  table = "role_entities",
  primary_key = { "role_id", "entity_id" },
  fields = {
    role_id = {
      type = "id",
      required = true,
    },
    entity_id = {
      type = "id",
      required = true,
    },
    entity_type = {
      type = "string",
      required = true,
      enum = { "workspace", "entity" },
    },
    permissions = {
      type = "number",
      required = true,
    },
    negative = {
      type = "boolean",
      required = true,
      default = false,
    },
  },
}
