return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "routes" ADD "path_handling" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE routes ADD path_handling text;
    ]],
  },
}
