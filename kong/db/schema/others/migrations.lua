-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
