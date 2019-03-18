return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS sessions(
        id            uuid,
        session_id    text UNIQUE,
        expires       int,
        data          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        ttl           timestamp with time zone,
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('session_sessions_expires_idx')) IS NULL THEN
          CREATE INDEX session_sessions_expires_idx ON sessions (expires);
        END IF;
      END$$;
    ]],
  },
  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS sessions(
        id            uuid,
        session_id    text,
        expires       int,
        data          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON sessions (session_id);
      CREATE INDEX IF NOT EXISTS ON sessions (expires);
    ]],
  },
}
