return {
  table = "workspaces",
  primary_key = { "id" },
  cache_key = { "id" },
  workspaceable = true,
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    name = {
      type = "string",
      required = true,
      unique = true,
    },
    comment = {
      type = "string",
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  },
}
