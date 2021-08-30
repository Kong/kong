-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations_230_260 = require "kong.db.migrations.operations.230_to_260"


return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "admins" ADD "username_lower" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      UPDATE admins SET username_lower=LOWER(username);
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE admins ADD username_lower TEXT;

      CREATE INDEX IF NOT EXISTS admins_username_lower_idx ON admins(username_lower);
    ]],
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())

      return operations_230_260.cassandra_copy_usernames_to_lower(coordinator, "admins")
    end,
  },
}
