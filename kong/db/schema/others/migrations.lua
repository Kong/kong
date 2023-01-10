return {
  name = "migration",
  fields = {
    { name      = { type = "string", required = true } },
    {
      postgres  = {
        type = "record", required = true,
        fields = {
          { up_t = { type = "function" } },
          { up = { type = "string", len_min = 0 } },
          { up_f = { type = "function" } },
          { teardown = { type = "function" } },
        },
      },
    },
    {
      cassandra = {
        type = "record", required = true,
        fields = {
          { up_t = { type = "function" } },
          { up = { type = "string", len_min = 0 } },
          { up_f = { type = "function" } },
          { teardown = { type = "function" } },
        },
      }
    },
  },
  entity_checks = {
    {
      at_least_one_of = {
        "postgres.up_t", "postgres.up", "postgres.up_f", "postgres.teardown",
        "postgres.up_t", "cassandra.up", "cassandra.up_f", "cassandra.teardown",
      },
    },
  },
}
