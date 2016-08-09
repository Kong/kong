
-- This schema defines a sequential list of updates to the upstream/loadbalancer algorithm
-- hence entries cannot be deleted or modified. Only new ones appended that will overrule
-- previous entries.

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
      -- in 'hostname:port' format
      type = "string",
      unique = true, 
      required = true,
    },
    weight = {
      -- weight in the landbalancer algorithm.
      -- to disable an entry, set the weight to 0
      type = "number",
      default = 100,
      func = function(value) return (value >= 0 and value <= 1000), "weight must be between 0 and 1000" end,
    },
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
