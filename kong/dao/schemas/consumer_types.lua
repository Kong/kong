return {
  table = "consumer_types",
  primary_key = { "id" },
  cache_key = { "id", "name" },
  fields = {
    id = { type = "integer", required = true },
    name = { type = "string" },
    comment = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true, required = true },
  },
}
