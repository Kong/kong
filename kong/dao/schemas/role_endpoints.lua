return {
  table = "role_endpoints",
  primary_key = { "id" },
  fields = {
    id = {
      type = "id",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    role_id = {
      type = "id",
      required = true,
    },
    workspace = {
      type = "string",
      required = true,
      default = "default",
    },
    endpoint = {
      type = "string",
      required = true,
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
