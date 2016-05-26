return {
  {
    name = "2015-08-03-132400_init_oauth2",
    up = [[
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
        authenticated_userid text,
        scope text,
        created_at timestamp,
        PRIMARY KEY (id)
      ) WITH default_time_to_live = 300;

      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(code);
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(authenticated_userid);

      CREATE TABLE IF NOT EXISTS oauth2_tokens(
        id uuid,
        credential_id uuid,
        access_token text,
        token_type text,
        refresh_token text,
        expires_in int,
        authenticated_userid text,
        scope text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(access_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(refresh_token);
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(authenticated_userid);
    ]],
    down = [[
      DROP TABLE oauth2_credentials;
      DROP TABLE oauth2_authorization_codes;
      DROP TABLE oauth2_tokens;
    ]]
  },
  {
    name = "2015-08-24-215800_cascade_delete_index",
    up = [[
      CREATE INDEX IF NOT EXISTS oauth2_credential_id_idx ON oauth2_tokens(credential_id);
    ]],
    down = [[
      DROP INDEX oauth2_credential_id_idx;
    ]]
  },
  {
    name = "2016-02-29-435612_remove_ttl",
    up = [[
      ALTER TABLE oauth2_authorization_codes WITH default_time_to_live = 0;
    ]],
    down = [[
      ALTER TABLE oauth2_authorization_codes WITH default_time_to_live = 3600;
    ]]
  },
  {
    name = "2016-04-14-283949_serialize_redirect_uri",
    up = function(_, _, factory)
      local json = require "cjson"
      local apps, err = factory.oauth2_credentials.db:find_all('oauth2_credentials', nil, nil);
      if err then
        return err
      end
      for _, app in ipairs(apps) do
        local redirect_uri = {};
        redirect_uri[1] = app.redirect_uri
        local redirect_uri_str = json.encode(redirect_uri)
        local req = "UPDATE oauth2_credentials SET redirect_uri='"..redirect_uri_str.."' WHERE id="..app.id
        local _, err = factory.oauth2_credentials.db:queries(req)
        if err then
          return err
        end
      end
    end,
    down = function(_,_,factory)
      local apps, err = factory.oauth2_credentials:find_all()
      if err then
        return err
      end
      for _, app in ipairs(apps) do
        local redirect_uri = app.redirect_uri[1]
        local req = "UPDATE oauth2_credentials SET redirect_uri='"..redirect_uri.."' WHERE id="..app.id
        local _, err = factory.oauth2_credentials.db:queries(req)
        if err then
          return err
        end
      end
    end
  }
}
