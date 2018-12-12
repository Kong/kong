local migrations = {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        id            uuid,
        issuer        text,
        configuration text,
        keys          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_issuers (issuer);

      CREATE TABLE IF NOT EXISTS oic_signout (
        id            uuid,
        jti           text,
        iss           text,
        sid           text,
        sub           text,
        aud           text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_signout (iss);
      CREATE INDEX IF NOT EXISTS ON oic_signout (sid);
      CREATE INDEX IF NOT EXISTS ON oic_signout (sub);
      CREATE INDEX IF NOT EXISTS ON oic_signout (jti);

      CREATE TABLE IF NOT EXISTS oic_session (
        id            uuid,
        sid           text,
        expires       int,
        data          text,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_session (sid);
      CREATE INDEX IF NOT EXISTS ON oic_session (expires);

      CREATE TABLE IF NOT EXISTS oic_revoked (
        id            uuid,
        hash          text,
        expires       int,
        created_at    timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oic_revoked (hash);
      CREATE INDEX IF NOT EXISTS ON oic_revoked (expires);
    ]],
    down = [[
      DROP TABLE EXISTS oic_issuers;
      DROP TABLE EXISTS oic_signout;
      DROP TABLE EXISTS oic_session;
      DROP TABLE EXISTS oic_revoked;
    ]],
  },
  {
    name = "2017-08-09-160000-add-secret-used-for-sessions",
    up = [[
      ALTER TABLE oic_issuers ADD secret text;
    ]],
    down = [[
      ALTER TABLE oic_issuers DROP secret;
    ]],
  },
  {
    name = "2018-12-12-160000-drop-unused",
    up = [[
      DROP TABLE IF EXISTS oic_signout;
      DROP TABLE IF EXISTS oic_session;
      DROP TABLE IF EXISTS oic_revoked;
    ]],
  },
}

return migrations
