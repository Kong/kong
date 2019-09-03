return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY jwt_secrets ADD tags TEXT[];
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS jwtsecrets_tags_idex_tags_idx ON jwt_secrets USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS jwtsecrets_sync_tags_trigger ON jwt_secrets;

      DO $$
      BEGIN
        CREATE TRIGGER jwtsecrets_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON jwt_secrets
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

    ]],
  },
  cassandra = {
    up = [[
      ALTER TABLE jwt_secrets ADD tags set<text>;
    ]],
  }
}
