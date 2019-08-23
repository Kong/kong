return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "upstreams" ADD "host_header" TEXT;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[
      ALTER TABLE upstreams ADD host_header text;
    ]],
  },
}
