return {
  table = "workspace_entities",
  primary_key = { "workspace_id", "entity_id" },
  fields = {
    workspace_id = {
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
  },
}
