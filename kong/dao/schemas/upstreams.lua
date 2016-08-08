
return {
  table = "upstreams",
  primary_key = {"id", "name"},
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
    name = {
      type = "string", 
      unique = true, 
      required = true,
    },
    slots = {
      type = "number",
      default = 1000,
    },
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
