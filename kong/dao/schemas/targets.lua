
return {
  table = "upstreams",
  primary_key = {"id"},
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
    upstream_id = {
      type = "id",
      foreign = "upstreams:id"
    },
    target = {
      type = "string",   -- "hostname:port" format
      unique = true, 
      required = true,
    },
    weight = {
      type = "number",
      default = 1000,
    },
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
