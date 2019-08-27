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
