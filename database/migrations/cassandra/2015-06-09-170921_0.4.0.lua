local Migration = {
  name = "2015-06-09-170921_0.4.0",

  up = function(options)
    return [[
      CREATE TABLE IF NOT EXISTS oauth2_credentials(
        id uuid,
        name text,
        consumer_id uuid,
        client_id text,
        client_secret text,
        redirect_uri text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(consumer_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_id);
      CREATE INDEX IF NOT EXISTS ON oauth2_credentials(client_secret);

      CREATE TABLE IF NOT EXISTS oauth2_authorization_codes(
        id uuid,
        code text,
        authenticated_username text,
        authenticated_userid text,
        scope text,
        created_at timestamp,
        PRIMARY KEY (id)
      ) WITH default_time_to_live = 300;

      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(code);

      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id uuid,
        credential_id uuid,
        access_token text,
        token_type text,
        refresh_token text,
        expires_in int,
        authenticated_username text,
        authenticated_userid text,
        scope text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(access_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(refresh_token);

    ]]
  end,

  down = function(options)
    return [[
      DROP TABLE oauth2_credentials;
      DROP TABLE oauth2_authorization_codes;
      DROP TABLE oauth2_tokens;
    ]]
  end
}

return Migration