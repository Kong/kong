-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
