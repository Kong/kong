return {
  table = "rbac_resources",
  primary_key = { "id" },
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    name = {
      type = "string",
      required = true,
    },
    bit_pos = {
      type = "number",
      required = true,
    },
  },
}
