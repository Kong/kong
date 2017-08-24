return {
  table = "ssl_certificates",
  primary_key = { "id" },
  fields = {
    id = { type = "id", dao_insert_value = true, required = true },
    cert = { type = "string", required = true },
    key = { type = "string", required = true },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  },
}
