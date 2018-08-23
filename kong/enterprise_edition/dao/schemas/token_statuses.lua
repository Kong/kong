return {
  table = "token_statuses",
  primary_key = { "id" },
  cache_key = { "id", "name" },
  fields = {
    id = { type = "integer", required = true },
    name = { type = "string" },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true, required = true },
  }
}
