local plugin_config_iterator = require("kong.dao.migrations.helpers").plugin_config_iterator

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
  },
  {
    name = "2016-07-15-oauth2_code_credential_id",
    up = [[
      DELETE FROM oauth2_authorization_codes;
      ALTER TABLE oauth2_authorization_codes ADD COLUMN credential_id uuid REFERENCES oauth2_credentials (id) ON DELETE CASCADE;
    ]],
    down = [[
      ALTER TABLE oauth2_authorization_codes DROP COLUMN credential_id;
    ]]
  },
  {
    name = "2016-12-22-283949_serialize_redirect_uri",
    up = function(_, _, factory)
      local schema = factory.oauth2_credentials.schema
      schema.fields.redirect_uri.type = "string"
      local json = require "cjson"
      local apps, err = factory.oauth2_credentials.db:find_all('oauth2_credentials', nil, schema);
      if err then
        return err
      end
      for _, app in ipairs(apps) do
        local redirect_uri = {};
        redirect_uri[1] = app.redirect_uri
        local redirect_uri_str = json.encode(redirect_uri)
        local req = "UPDATE oauth2_credentials SET redirect_uri='" .. redirect_uri_str .. "' WHERE id='" .. app.id .. "'"
        local _, err = factory.oauth2_credentials.db:queries(req)
        if err then
          return err
        end
      end
      schema.fields.redirect_uri.type = "array"
    end,
    down = function(_,_,factory)
      local apps, err = factory.oauth2_credentials:find_all()
      if err then
        return err
      end
      for _, app in ipairs(apps) do
        local redirect_uri = app.redirect_uri[1]
        local req = "UPDATE oauth2_credentials SET redirect_uri='" .. redirect_uri .. "' WHERE id='" .. app.id .. "'"
        local _, err = factory.oauth2_credentials.db:queries(req)
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2016-09-19-oauth2_api_id",
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD COLUMN api_id uuid REFERENCES apis (id) ON DELETE CASCADE;
      ALTER TABLE oauth2_tokens ADD COLUMN api_id uuid REFERENCES apis (id) ON DELETE CASCADE;
    ]],
    down = [[
      ALTER TABLE oauth2_authorization_codes DROP COLUMN api_id;
      ALTER TABLE oauth2_tokens DROP COLUMN api_id;
    ]]
  },
  {
    name = "2016-12-15-set_global_credentials",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all({name = "oauth2"})
      if err then
        return err
      end
      for _, row in ipairs(rows) do
        row.config.global_credentials = true

        local _, err = dao.plugins:update(row, row)
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2017-04-24-oauth2_client_secret_not_unique",
    up = [[
      ALTER TABLE oauth2_credentials DROP CONSTRAINT IF EXISTS oauth2_credentials_client_secret_key;
    ]],
    down = [[
      ALTER TABLE oauth2_credentials ADD CONSTRAINT oauth2_credentials_client_secret_key UNIQUE(client_secret);
    ]],
  },
  {
    name = "2017-10-19-set_auth_header_name_default",
    up = function(_, _, dao)
      for ok, config, update in plugin_config_iterator(dao, "oauth2") do
        if not ok then
          return config
        end
        if config.auth_header_name == nil then
          config.auth_header_name = "authorization"
          local _, err = update(config)
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  },
  {
    name = "2017-10-11-oauth2_new_refresh_token_ttl_config_value",
    up = function(_, _, dao)
      for ok, config, update in plugin_config_iterator(dao, "oauth2") do
        if not ok then
          return config
        end
        if config.refresh_token_ttl == nil then
          config.refresh_token_ttl = 1209600
          local _, err = update(config)
          if err then
            return err
          end
        end
      end
    end,
    down = function(_, _, dao) end  -- not implemented
  }
}
