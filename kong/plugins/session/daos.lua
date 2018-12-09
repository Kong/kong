return {
  sessions = {
    primary_key = { "id" },
    cache_key = { "session_id" },
    table = "sessions",
    fields = {
      id = {
        type = "id",
        dao_insert_value = true
      },
      session_id = {
        type = "text",
        unique = true,
        required = true
      },
      expires = {
        type = "number",
      },
      data = {
        type = "text",
      },
      created_at = {
        type = "timestamp",
        immutable = true,
        dao_insert_value = true,
      },
    }
  }
}
