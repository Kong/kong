return {
  {
    name = "2015-08-03-132400_init_oauth2",
    up = [[
      CREATE TABLE IF NOT EXISTS oauth2_credentials(
        id uuid,
        name text,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        client_id text UNIQUE,
        client_secret text UNIQUE,
        redirect_uri text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oauth2_credentials_consumer_idx')) IS NULL THEN
          CREATE INDEX oauth2_credentials_consumer_idx ON oauth2_credentials(consumer_id);
        END IF;
        IF (SELECT to_regclass('oauth2_credentials_client_idx')) IS NULL THEN
          CREATE INDEX oauth2_credentials_client_idx ON oauth2_credentials(client_id);
        END IF;
        IF (SELECT to_regclass('oauth2_credentials_secret_idx')) IS NULL THEN
          CREATE INDEX oauth2_credentials_secret_idx ON oauth2_credentials(client_secret);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS oauth2_authorization_codes(
        id uuid,
        code text UNIQUE,
        authenticated_userid text,
        scope text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oauth2_autorization_code_idx')) IS NULL THEN
          CREATE INDEX oauth2_autorization_code_idx ON oauth2_authorization_codes(code);
        END IF;
        IF (SELECT to_regclass('oauth2_authorization_userid_idx')) IS NULL THEN
          CREATE INDEX oauth2_authorization_userid_idx ON oauth2_authorization_codes(authenticated_userid);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id uuid,
        credential_id uuid REFERENCES oauth2_credentials (id) ON DELETE CASCADE,
        access_token text UNIQUE,
        token_type text,
        refresh_token text UNIQUE,
        expires_in int,
        authenticated_userid text,
        scope text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('oauth2_accesstoken_idx')) IS NULL THEN
          CREATE INDEX oauth2_accesstoken_idx ON oauth2_tokens(access_token);
        END IF;
        IF (SELECT to_regclass('oauth2_token_refresh_idx')) IS NULL THEN
          CREATE INDEX oauth2_token_refresh_idx ON oauth2_tokens(refresh_token);
        END IF;
        IF (SELECT to_regclass('oauth2_token_userid_idx')) IS NULL THEN
          CREATE INDEX oauth2_token_userid_idx ON oauth2_tokens(authenticated_userid);
        END IF;
      END$$;
    ]],
    down =  [[
      DROP TABLE oauth2_credentials;
      DROP TABLE oauth2_authorization_codes;
      DROP TABLE oauth2_tokens;
    ]]
  }
}
