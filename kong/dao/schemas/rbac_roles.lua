return {
  table = "rbac_roles",
  workspaceable = true,
  primary_key = { "id" },
  cache_key = { "id" },
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
    is_default = {
      type = "boolean",
      required = true,
      default = false,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  }
}
