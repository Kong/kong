return {
  {
    name = "2015-06-09-jwt-auth",
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_secrets(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        key text UNIQUE,
        secret text UNIQUE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('jwt_secrets_key')) IS NULL THEN
          CREATE INDEX jwt_secrets_key ON jwt_secrets(key);
        END IF;
        IF (SELECT to_regclass('jwt_secrets_secret')) IS NULL THEN
          CREATE INDEX jwt_secrets_secret ON jwt_secrets(secret);
        END IF;
        IF (SELECT to_regclass('jwt_secrets_consumer_id')) IS NULL THEN
          CREATE INDEX jwt_secrets_consumer_id ON jwt_secrets(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE jwt_secrets;
    ]]
  },
  {
    name = "2016-03-07-jwt-alg",
    up = [[
      ALTER TABLE jwt_secrets ADD COLUMN algorithm text;
      ALTER TABLE jwt_secrets ADD COLUMN rsa_public_key text;
    ]],
    down = [[
      ALTER TABLE jwt_secrets DROP COLUMN algorithm;
      ALTER TABLE jwt_secrets DROP COLUMN rsa_public_key;
    ]]
  }
}
