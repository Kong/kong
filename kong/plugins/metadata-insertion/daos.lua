local SCHEMA = {
  primary_key = { "id" },
  table = "metadata_keyvaluestore",
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", immutable = true, dao_insert_value = true },
    consumer_id = { type = "id", required = true, foreign = "consumers:id" },
    key = { type = "string", required = true },
    value = { type = "string", required = true }
  },
  marshall_event = function(self, t)
    return { id = t.id, consumer_id = t.consumer_id, key = t.key }
  end
}

return { metadata_keyvaluestore = SCHEMA }
