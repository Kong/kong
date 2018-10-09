return {
  table = "workspace_entity_counters",
  workspaceable = false,
  primary_key = { "workspace_id", "entity_type"},
  fields = {
    workspace_id = { type = "id", required = true, foreign = "workspaces:id" },
    entity_type = { type = "string", required = true },
    count = { type = "number"},
  }
}
