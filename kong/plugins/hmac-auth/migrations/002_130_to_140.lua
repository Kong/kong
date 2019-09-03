return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY hmacauth_credentials ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS hmacauth_tags_idex_tags_idx ON hmacauth_credentials USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS hmacauth_sync_tags_trigger ON hmacauth_credentials;

      DO $$
      BEGIN
        CREATE TRIGGER hmacauth_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON hmacauth_credentials
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

    ]],
  },
  cassandra = {
    up = [[
      ALTER TABLE hmacauth_credentials ADD tags set<text>;
    ]],
  }
}
