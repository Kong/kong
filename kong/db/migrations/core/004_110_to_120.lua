return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY services ADD path_separated BOOLEAN;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE services ADD path_separated boolean;
    ]],
  },
}
