return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "applications" ADD "custom_id" TEXT UNIQUE;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
    teardown = function(connector)
    end,
  },

  cassandra = {
    up = [[
      ALTER TABLE applications ADD custom_id text;
      CREATE INDEX IF NOT EXISTS applications_custom_id_idx ON applications(custom_id);
    ]],
    teardown = function(connector)
    end,
  }
}
