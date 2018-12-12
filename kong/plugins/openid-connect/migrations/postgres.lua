local migrations = {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        id            uuid,
        issuer        text UNIQUE,
        configuration text,
        keys          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_issuers_idx')) IS NULL THEN
          CREATE INDEX oic_issuers_idx ON oic_issuers (issuer);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_signout (
        id            uuid,
        jti           text,
        iss           text,
        sid           text,
        sub           text,
        aud           text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_iss_idx')) IS NULL THEN
          CREATE INDEX oic_signout_iss_idx ON oic_signout (iss);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_sid_idx')) IS NULL THEN
          CREATE INDEX oic_signout_sid_idx ON oic_signout (sid);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_sub_idx')) IS NULL THEN
          CREATE INDEX oic_signout_sub_idx ON oic_signout (sub);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_signout_jti_idx')) IS NULL THEN
          CREATE INDEX oic_signout_jti_idx ON oic_signout (jti);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_session (
        id            uuid,
        sid           text UNIQUE,
        expires       int,
        data          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_sid_idx')) IS NULL THEN
          CREATE INDEX oic_session_sid_idx ON oic_session (sid);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_exp_idx')) IS NULL THEN
          CREATE INDEX oic_session_exp_idx ON oic_session (expires);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS oic_revoked (
        id            uuid,
        hash          text,
        expires       int,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_hash_idx')) IS NULL THEN
          CREATE INDEX oic_session_hash_idx ON oic_revoked (hash);
        END IF;
      END$$;

      DO $$
      BEGIN
        IF (SELECT to_regclass('oic_session_exp_idx')) IS NULL THEN
          CREATE INDEX oic_session_exp_idx ON oic_revoked (expires);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE IF EXISTS oic_issuers CASCADE;
      DROP TABLE IF EXISTS oic_signout CASCADE;
      DROP TABLE IF EXISTS oic_session CASCADE;
      DROP TABLE IF EXISTS oic_revoked CASCADE;
    ]]
  },
  {
    name = "2017-08-09-160000-add-secret-used-for-sessions",
    up = [[
      ALTER TABLE oic_issuers ADD COLUMN secret text;
    ]],
    down = [[
      ALTER TABLE oic_issuers ADD COLUMN secret text;
    ]],
  },
  {
    name = "2018-12-12-160000-drop-unused",
    up = [[
      DROP TABLE IF EXISTS oic_signout CASCADE;
      DROP TABLE IF EXISTS oic_session CASCADE;
      DROP TABLE IF EXISTS oic_revoked CASCADE;
      DROP INDEX IF EXISTS oic_issuers_idx;

      ALTER TABLE IF EXISTS ONLY "oic_issuers"
        ALTER "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC',
        ALTER "created_at" SET DEFAULT CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC';
    ]],
  },
}

return migrations
