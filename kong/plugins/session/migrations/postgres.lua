return {
  {
    name = "2018-11-30-133200_init_session",
    up = [[
      CREATE TABLE IF NOT EXISTS sessions(
        id            uuid,
        session_id    text UNIQUE,
        expires       int,
        data          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$	
      BEGIN	
        IF (SELECT to_regclass('session_sessions_session_id_idx')) IS NULL THEN	
          CREATE INDEX session_sessions_session_id_idx ON sessions (session_id);	
        END IF;	
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('session_sessions_expires_idx')) IS NULL THEN
          CREATE INDEX session_sessions_expires_idx ON sessions (expires);
        END IF;
      END$$;
    ]],
    down =  [[
      DROP TABLE sessions;
    ]]
  }
}
