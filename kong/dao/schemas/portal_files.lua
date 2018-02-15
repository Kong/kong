return {
  table = "portal_files",
  primary_key = {"id"},
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    auth = {
      type = "boolean",
      default = true
    },
    name = {
      type = "string",
      unique = true,
      required = true,
    },
    type = {
      type = "string",
      required = true,
    },
    contents = {
      type = "string",
      required = true
    }
  },
}
