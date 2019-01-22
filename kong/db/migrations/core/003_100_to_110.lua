return {
  postgres = {
    up = [[

      UPDATE consumers SET created_at = DATE_TRUNC('seconds', created_at);
      UPDATE plugins   SET created_at = DATE_TRUNC('seconds', created_at);
      UPDATE upstreams SET created_at = DATE_TRUNC('seconds', created_at);
      UPDATE targets   SET created_at = DATE_TRUNC('milliseconds', created_at);

      DROP FUNCTION IF EXISTS "upsert_ttl" (TEXT, UUID, TEXT, TEXT, TIMESTAMP WITHOUT TIME ZONE);

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD "protocols" TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;
    ]],
  },

  cassandra = {
    up = [[

      ALTER TABLE plugins ADD protocols set<text>;

    ]],
  },
}
