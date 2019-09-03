return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY acls ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS acls_tags_idex_tags_idx ON acls USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS acls_sync_tags_trigger ON acls;

      DO $$
      BEGIN
        CREATE TRIGGER acls_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON acls
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

    ]],
  },
  cassandra = {
    up = [[
      ALTER TABLE acls ADD tags set<text>;
    ]],
  }
}
