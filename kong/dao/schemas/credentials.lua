return {
  table = "credentials",
  primary_key = { "id" },
  cache_key = { "id", "name" },
  fields = {
    id = { type = "id", required = true },
    consumer_id = { type = "id", foreign = "consumers:id" },
    consumer_type = { type = "integer", required = true },
    plugin = { type = "string", required = true },
    blob = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true, required = true },
  },
}
