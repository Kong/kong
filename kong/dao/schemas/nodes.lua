return {
  table = "nodes",
  primary_key = {"name"},
  fields = {
    name = {type = "string"},
    created_at = {type = "timestamp", dao_insert_value = true,required = true},
    cluster_listening_address = {type = "string", required = true}
  },
  marshall_event = function(self, t)
    return { name = t.name }
  end
}
