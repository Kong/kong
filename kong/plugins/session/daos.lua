return {
  sessions = {
    primary_key = { "id" },
    cache_key = { "sid" },
    table = "sessions",
    fields = {
      id = {
        type = "id",
        dao_insert_value = true
      },
      sid = {
        type = "text",
        unique = true,
        required = true
      },
      expires = {
        type = "number"
      },
      data = {
        type = "text"
      },
      created_at = {
        type = "timestamp",
        immutable = true,
        dao_insert_value = true
      }
    }
  }
}
