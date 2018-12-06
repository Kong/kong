return {
  {
    name = "2018-11-30-133200_init_session",
    up = [[
      CREATE TABLE IF NOT EXISTS sessions(
        id            uuid,
        expires       int,
        data          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON sessions (expires);
    ]],
    down = [[
      DROP TABLE sessions;
    ]]
  }
}
