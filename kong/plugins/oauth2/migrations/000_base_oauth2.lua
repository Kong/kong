return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "oauth2_credentials" (
        "id"             UUID                         PRIMARY KEY,
        "created_at"     TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "name"           TEXT,
        "consumer_id"    UUID                         REFERENCES "consumers" ("id") ON DELETE CASCADE,
        "client_id"      TEXT                         UNIQUE,
        "client_secret"  TEXT,
        "redirect_uri"   TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_credentials_consumer_idx" ON "oauth2_credentials" ("consumer_id");
      CREATE INDEX IF NOT EXISTS "oauth2_credentials_secret_idx"   ON "oauth2_credentials" ("client_secret");



      CREATE TABLE IF NOT EXISTS "oauth2_authorization_codes" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "credential_id"         UUID                         REFERENCES "oauth2_credentials" ("id") ON DELETE CASCADE,
        "service_id"            UUID                         REFERENCES "services" ("id") ON DELETE CASCADE,
        "api_id"                UUID                         REFERENCES "apis" ("id") ON DELETE CASCADE,
        "code"                  TEXT                         UNIQUE,
        "authenticated_userid"  TEXT,
        "scope"                 TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_authorization_userid_idx" ON "oauth2_authorization_codes" ("authenticated_userid");



      CREATE TABLE IF NOT EXISTS "oauth2_tokens" (
        "id"                    UUID                         PRIMARY KEY,
        "created_at"            TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "credential_id"         UUID                         REFERENCES "oauth2_credentials" ("id") ON DELETE CASCADE,
        "service_id"            UUID                         REFERENCES "services" ("id") ON DELETE CASCADE,
        "api_id"                UUID                         REFERENCES "apis" ("id") ON DELETE CASCADE,
        "access_token"          TEXT                         UNIQUE,
        "refresh_token"         TEXT                         UNIQUE,
        "token_type"            TEXT,
        "expires_in"            INTEGER,
        "authenticated_userid"  TEXT,
        "scope"                 TEXT
      );

      CREATE INDEX IF NOT EXISTS "oauth2_token_userid_idx" ON "oauth2_tokens" ("authenticated_userid");
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS oauth2_credentials(
        id            uuid PRIMARY KEY,
        created_at    timestamp,
        consumer_id   uuid,
        client_id     text,
        client_secret text,
        name          text,
        redirect_uri  text
      );
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_secret);



      CREATE TABLE IF NOT EXISTS oauth2_authorization_codes(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        service_id           uuid,
        api_id               uuid,
        credential_id        uuid,
        authenticated_userid text,
        code                 text,
        scope                text
      ) WITH default_time_to_live = 300;
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(code);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(api_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(service_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(credential_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(authenticated_userid);



      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        service_id           uuid,
        api_id               uuid,
        credential_id        uuid,
        access_token         text,
        authenticated_userid text,
        refresh_token        text,
        scope                text,
        token_type           text,
        expires_in           int
      );
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(api_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(service_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(access_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(refresh_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(credential_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(authenticated_userid);
    ]],
  },
}
