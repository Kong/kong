return {
  table = "rbac_perms",
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
    resources = {
      type = "number",
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
      required = true,
    },
  },
}
