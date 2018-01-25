return {
  table = "role_endpoints",
  primary_key = { "role_id", "workspace", "endpoint" },
  fields = {
    role_id = {
      type = "id",
      required = true,
      immutable = true,
    },
    workspace = {
      type = "string",
      required = true,
      default = "default",
      immutable = true,
    },
    endpoint = {
      type = "string",
      required = true,
      immutable = true,
    },
    actions = {
      type = "number",
      required = true,
    },
    negative = {
      type = "boolean",
      required = true,
      default = false,
    },
    comment = {
      type = "string",
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
    },
  },
}
