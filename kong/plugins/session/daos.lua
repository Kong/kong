return {
  sessions = {
    primary_key = { "id" },
    table = "sessions",
    fields = {
      id = {
        type = "text",
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
