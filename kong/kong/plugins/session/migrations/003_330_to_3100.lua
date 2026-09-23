return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS session_metadatas(
        id            uuid,
        session_id    uuid                    REFERENCES "sessions" ("id") ON DELETE CASCADE,
        sid           text,
        subject       text,
        audience      text,
        created_at    timestamp WITH TIME ZONE,
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "session_id_idx" ON "session_metadatas" ("session_id");
        CREATE INDEX IF NOT EXISTS "subject_audience_idx" ON "session_metadatas" ("subject", "audience");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
