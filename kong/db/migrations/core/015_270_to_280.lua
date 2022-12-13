return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        -- we don't want to recreate vaults_beta again, if this migration is ran twice
        IF (SELECT to_regclass('vaults_tags_idx')) IS NULL THEN
          CREATE TABLE IF NOT EXISTS "vaults_beta" (
            "id"           UUID                      PRIMARY KEY,
            "ws_id"        UUID                      REFERENCES "workspaces" ("id"),
            "prefix"       TEXT                      UNIQUE,
            "name"         TEXT                      NOT NULL,
            "description"  TEXT,
            "config"       JSONB                     NOT NULL,
            "created_at"   TIMESTAMP WITH TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
            "updated_at"   TIMESTAMP WITH TIME ZONE,
            "tags"         TEXT[],
            UNIQUE ("id", "ws_id"),
            UNIQUE ("prefix", "ws_id")
          );

          DROP TRIGGER IF EXISTS "vaults_beta_sync_tags_trigger" ON "vaults_beta";

          BEGIN
            CREATE INDEX IF NOT EXISTS "vaults_beta_tags_idx" ON "vaults_beta" USING GIN ("tags");
          EXCEPTION WHEN UNDEFINED_COLUMN THEN
            -- Do nothing, accept existing state
          END;

          BEGIN
            CREATE TRIGGER "vaults_beta_sync_tags_trigger"
            AFTER INSERT OR UPDATE OF "tags" OR DELETE ON "vaults_beta"
            FOR EACH ROW
            EXECUTE PROCEDURE sync_tags();
          EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
            -- Do nothing, accept existing state
          END;
        END IF;
      END$$;
    ]]
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS vaults_beta (
        id          uuid,
        ws_id       uuid,
        prefix      text,
        name        text,
        description text,
        config      text,
        created_at  timestamp,
        updated_at  timestamp,
        tags        set<text>,
        PRIMARY KEY (id)
      );
      CREATE INDEX IF NOT EXISTS vaults_beta_prefix_idx ON vaults_beta (prefix);
      CREATE INDEX IF NOT EXISTS vaults_beta_ws_id_idx  ON vaults_beta (ws_id);
    ]]
  },
}
