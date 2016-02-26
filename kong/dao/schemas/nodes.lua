return {
  name = "Node",
  table = "nodes",
  primary_key = {"name"},
  fields = {
    name = { type = "string" },
    created_at = { type = "timestamp", dao_insert_value = true },
    cluster_listening_address = { type = "string", required = true }
  }
}
