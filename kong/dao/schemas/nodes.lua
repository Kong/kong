return {
  name = "Node",
  primary_key = {"name"},
  fields = {
    name = { type = "string" },
    created_at = { type = "timestamp", dao_insert_value = true },
    cluster_listening_address = { type = "string", queryable = true, required = true }
  }
}
