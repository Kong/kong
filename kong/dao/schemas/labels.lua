return {
  table = "labels",
  primary_key = {"id"},
  cache_key = { "id" },
  fields = {
    id = {
      type = "id", 
      dao_insert_value = true, 
      required = true
    },
    created_at = {
      type = "timestamp", 
      immutable = true, 
      dao_insert_value = true, 
      required = true
    },
    name = {
      type = "string", 
      unique = true
    },
  },
}
