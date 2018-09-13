local plugin_config_iterator = require("kong.dao.migrations.helpers").plugin_config_iterator
local cjson = require "cjson"

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
    up = function(_, _, dao)
      local coordinator = dao.db:get_coordinator()
      local q1 = [[
        SELECT id, redirect_uri FROM oauth2_credentials;
      ]]
      for rows, err in coordinator:iterate(q1) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          local redirect_uri_str = cjson.encode({ row.redirect_uri })
          local q = string.format("UPDATE oauth2_credentials SET redirect_uri='%' WHERE id='%s';",
                                  redirect_uri_str, row.id)
          local _, err = dao.db:query(q)
          if err then
            return err
          end
        end
      end
    end,
    down = function(_,_,dao)
      local coordinator = dao.db:get_coordinator()
      local q1 = [[
        SELECT id, redirect_uri FROM oauth2_credentials;
      ]]
      for rows, err in coordinator:iterate(q1) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          local redirect_uri = cjson.decode(row.redirect_uri)[1]
          local q = string.format("UPDATE oauth2_credentials SET redirect_uri='%' WHERE id='%s';",
                                  redirect_uri, row.id)
          local _, err = dao.db:query(q)
          if err then
            return err
          end
        end
      end
    end,
    ignore_error = "redirect_uri"
  },
  {
    name = "2016-07-15-oauth2_code_credential_id",
    up = [[
      TRUNCATE oauth2_authorization_codes;
      ALTER TABLE oauth2_authorization_codes ADD credential_id uuid;
    ]],
    down = [[
      ALTER TABLE oauth2_authorization_codes DROP credential_id;
    ]],
    ignore_error = "Invalid column name credential_id"
  },
  {
    name = "2016-09-19-oauth2_code_index",
    up = [[
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(credential_id);
    ]]
  },
  {
    name = "2016-09-19-oauth2_api_id",
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD api_id uuid;
      CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(api_id);

      ALTER TABLE oauth2_tokens ADD api_id uuid;
      CREATE INDEX IF NOT EXISTS ON oauth2_tokens(api_id);
    ]],
    down = [[
      ALTER TABLE oauth2_authorization_codes DROP api_id;
      ALTER TABLE oauth2_tokens DROP api_id;
    ]],
    ignore_error = "Invalid column name api_id",
  },
  {
    name = "2016-12-15-set_global_credentials",
    up = function(_, _, dao)
      for ok, config, update in plugin_config_iterator(dao, "oauth2") do
        if not ok then
          return config
        end
        config.global_credentials = true
        local _, err = update(config)
        if err then
          return err
        end
      end
    end
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
  },
  {
     name = "2018-01-09-oauth2_c_add_service_id",
     up = [[
       ALTER TABLE oauth2_authorization_codes ADD service_id uuid;
       CREATE INDEX IF NOT EXISTS ON oauth2_authorization_codes(service_id);

       ALTER TABLE oauth2_tokens ADD service_id uuid;
       CREATE INDEX IF NOT EXISTS ON oauth2_tokens(service_id);
     ]],
     down = [[
      ALTER TABLE oauth2_authorization_codes DROP service_id;
      ALTER TABLE oauth2_tokens DROP service_id;
     ]],
     ignore_error = "Invalid column name service_id"
  },
  {
    name = "2018-09-12-oauth2_cassandra_add_redirect_uris_field",
    up = [[
      ALTER TABLE oauth2_credentials ADD redirect_uris set<text>;
    ]],
    ignore_error = "Invalid column name redirect_uris",
  },
  {
    name = "2018-09-12-oauth2_cassandra_parse_redirect_uris",
    function(_, _, dao)
      local coordinator = dao.db:get_coordinator()
      local q1 = [[
        SELECT id, redirect_uri FROM oauth2_credentials;
      ]]
      for rows, err in coordinator:iterate(q1) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          local uris = cjson.decode(row.redirect_uri)
          local buffer = {}
          for i, uri in ipairs(uris) do
            buffer[i] = "'" .. uri .. "'"
          end
          local q = string.format("UPDATE oauth2_credentials SET redirect_uris = {%s} WHERE id = %s;",
                                  table.concat(buffer, ","), row.id)
          local _, err = dao.db:query(q)
          if err then
            return err
          end
        end
      end
    end,
    ignore_error = "Invalid column name redirect_uri",
  },
  {
    name = "2018-09-12-oauth2_cassandra_drop_redirect_uri",
    up = [[
      ALTER TABLE oauth2_credentials DROP redirect_uri;
    ]],
    ignore_error = "redirect_uri was not found",
  },
  {
    name = "2018-09-13-oauth2_cassandra_add_ttl_to_codes",
    up = [[
      ALTER TABLE oauth2_authorization_codes ADD ttl timestamp;
    ]],
    ignore_error = "Invalid column name ttl",
  },
  {
    name = "2018-09-13-oauth2_cassandra_fill_codes_ttl",
    up = function(_, _, dao)
      local coordinator = dao.db:get_coordinator()
      local q1 = [[
        SELECT id, created_at FROM oauth2_tokens;
      ]]
      for rows, err in coordinator:iterate(q1) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          local q = string.format("UPDATE oauth2_authorization_codes SET ttl = %d WHERE id = %s;",
                                  row.created_at + 300, row.id)
          local _, err = dao.db:query(q)
          if err then
            return err
          end
        end
      end
    end
  },
  {
    name = "2018-09-13-oauth2_cassandra_add_ttl_to_tokens",
    up = [[
      ALTER TABLE oauth2_tokens ADD ttl timestamp;
    ]],
    ignore_error = "Invalid column name ttl",
  },
  {
    name = "2018-09-13-oauth2_cassandra_fill_tokens_ttl",
    up = function(_, _, dao)
      local coordinator = dao.db:get_coordinator()
      local q1 = [[
        SELECT id, created_at, expires_in FROM oauth2_tokens;
      ]]
      for rows, err in coordinator:iterate(q1) do
        if err then
          return err
        end

        for _, row in ipairs(rows) do
          local q = string.format("UPDATE oauth2_tokens SET ttl = %d WHERE id = %s;",
                                  row.created_at + row.expires_in, row.id)
          local _, err = dao.db:query(q)
          if err then
            return err
          end
        end
      end
    end
  },
}
