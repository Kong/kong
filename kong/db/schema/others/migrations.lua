local strat_migration = {
  { up = { type = "string", required = true, len_min = 0 } },
  { teardown = { type = "function" } },
}


return {
  name = "migration",
  fields = {
    { name      = { type = "string", required = true } },
    { postgres  = { type = "record", required = true, fields = strat_migration } },
    { cassandra = { type = "record", required = true, fields = strat_migration } },
  },
}
