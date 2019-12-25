local start_migration = {
  { up = { type = "string", required = true, len_min = 0 } },
  { teardown = { type = "function" } },
}


return {
  name = "migration",
  fields = {
    { name      = { type = "string", required = true } },
    { postgres  = { type = "record", required = true, fields = start_migration } },
    { cassandra = { type = "record", required = true, fields = start_migration } },
  },
}
