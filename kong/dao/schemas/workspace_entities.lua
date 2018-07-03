return {
  table = "workspace_entities",
  primary_key = { "workspace_id", "entity_id", "unique_field_name" },
  fields = {
    workspace_id = {
      type = "id",
      required = true,
    },
    workspace_name = {
      type = "string",
      required = true,
    },
    entity_id = {
      type = "string",
      required = true,
    },
    entity_type = {
      type = "string",
      required = false,
    },
    unique_field_name = {
      type = "string",
      required = true,
    },
    unique_field_value = {
      type = "string",
      required = false,
    },
  },
}
