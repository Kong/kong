return {
  name = "migration",
  fields = {
    { name      = { type = "string", required = true } },
    {
      postgres  = {
        type = "record", required = true,
        fields = {
          { up = { type = "string", len_min = 0 } },
          { teardown = { type = "function" } },
        },
      },
    },
    {
      cassandra = {
        type = "record", required = true,
        fields = {
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
        "postgres.up", "postgres.teardown",
        "cassandra.up", "cassandra.up_f", "cassandra.teardown"
      },
    },
  },
}
