local SCHEMA = {
  primary_key = {"id"},
  table = "autogen_entities",
  api = {
    secondary_key = "name"
  },
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    name = { type = "string", required = true }
  }
}

return {some_entities = SCHEMA}