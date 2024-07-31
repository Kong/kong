-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


-- This migration updates plugin's config by removing timeout field as it's been deprecated (it then populates read_timeout, send_timeout and connect_timeout if they're not set)

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      UPDATE plugins
      SET config =
        jsonb_set(
          config,
          '{redis}',
          (config -> 'redis') ||
            jsonb_build_object(
              'read_timeout', case when (config #>> '{redis,read_timeout}') IS NULL then (config #>> '{redis,timeout}')::integer else (config #>> '{redis,read_timeout}')::integer end,
              'send_timeout', case when (config #>> '{redis,send_timeout}') IS NULL then (config #>> '{redis,timeout}')::integer else (config #>> '{redis,send_timeout}')::integer end,
              'connect_timeout', case when (config #>> '{redis,connect_timeout}') IS NULL then (config #>> '{redis,timeout}')::integer else (config #>> '{redis,connect_timeout}')::integer end
            )
        )
      WHERE name = 'graphql-rate-limiting-advanced';
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],

    teardown = function(connector, _)
      local sql = [[
        DO $$
        BEGIN
        UPDATE plugins
        SET config =
          jsonb_set(config, '{redis}', (config -> 'redis') - 'timeout')
        WHERE name = 'graphql-rate-limiting-advanced';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
      ]]
      assert(connector:query(sql))
      return true
    end,
  },
}
