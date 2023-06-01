-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
    postgres = {
      up = [[
        CREATE TABLE IF NOT EXISTS "ws_migrations_backup" (
            "entity_type"               TEXT,
            "entity_id"                 TEXT,
            "unique_field_name"         TEXT,
            "unique_field_value"        TEXT,
            "created_at"                TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC')
          );
      ]],
      teardown = function(connector)
      end,
    },
  }
  