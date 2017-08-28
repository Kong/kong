return {
  table = "ssl_servers_names",
  primary_key = { "name" },
  fields = {
    name = { type = "text", required = true, unique = true },
    ssl_certificate_id = { type = "id", foreign = "ssl_certificates:id" },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
  },
}
