return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS sessions(
        id            uuid,
        session_id    text UNIQUE,
        expires       int,
        data          text,
        created_at    timestamp WITH TIME ZONE,
        ttl           timestamp WITH TIME ZONE,
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS "session_sessions_expires_idx" ON "sessions" ("expires");
      EXCEPTION WHEN UNDEFINED_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
  },
}
