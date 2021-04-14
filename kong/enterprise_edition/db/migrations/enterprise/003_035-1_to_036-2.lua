-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY developers ADD custom_id text;
        ALTER TABLE IF EXISTS ONLY developers ADD CONSTRAINT developers_custom_id UNIQUE(custom_id);
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
    teardown = function(connector)
      -- Risky migrations
    end
  },

  cassandra = {
    up = [[
      ALTER TABLE developers ADD custom_id text;
      CREATE INDEX IF NOT EXISTS developers_custom_id_idx ON developers(custom_id);
    ]],
    teardown = function(connector, helpers)
      -- Risky migrations
    end
  },
}
