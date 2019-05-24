return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "log_serializers" (
        id      UUID PRIMARY KEY,
        name    TEXT UNIQUE,
        chunk   TEXT NOT NULL,
        tags    TEXT[]
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS log_serializers_tags_idx ON log_serializers USING GIN(tags);
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DROP TRIGGER IF EXISTS log_serializers_sync_tags_trigger ON log_serializers;

      DO $$
      BEGIN
        CREATE TRIGGER log_serializers_sync_tags_trigger
        AFTER INSERT OR UPDATE OF tags OR DELETE ON log_serializers
        FOR EACH ROW
        EXECUTE PROCEDURE sync_tags();
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS log_serializers(
        id      uuid PRIMARY KEY,
        name    text,
        chunk   text,
        tags    set<text>
      );

      CREATE INDEX IF NOT EXISTS log_serializers_name_idx ON log_serializers(name);
    ]],
  },
}
