local Migrations = {
  -- init schema migration
  {
    name = "2015-01-12-175310_init_schema",
    init = true,

    up = function(options)
      return [[
        CREATE KEYSPACE IF NOT EXISTS "]]..options.keyspace..[["
          WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

        USE "]]..options.keyspace..[[";

        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );

        CREATE TABLE IF NOT EXISTS consumers(
          id uuid,
          custom_id text,
          username text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON consumers(custom_id);
        CREATE INDEX IF NOT EXISTS ON consumers(username);

        CREATE TABLE IF NOT EXISTS apis(
          id uuid,
          name text,
          public_dns text,
          target_url text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON apis(name);
        CREATE INDEX IF NOT EXISTS ON apis(public_dns);

        CREATE TABLE IF NOT EXISTS plugins_configurations(
          id uuid,
          api_id uuid,
          consumer_id uuid,
          name text,
          value text, -- serialized plugin data
          enabled boolean,
          created_at timestamp,
          PRIMARY KEY (id, name)
        );

        CREATE INDEX IF NOT EXISTS ON plugins_configurations(name);
        CREATE INDEX IF NOT EXISTS ON plugins_configurations(api_id);
        CREATE INDEX IF NOT EXISTS ON plugins_configurations(consumer_id);
      ]]
    end,

    down = function(options)
      return [[
        DROP KEYSPACE "]]..options.keyspace..[[";
      ]]
    end
  },

  -- 0.3.0
  {
    name = "2015-05-22-235608_0.3.0",

    up = function(options)
      return [[
        ALTER TABLE apis ADD path text;
        ALTER TABLE apis ADD strip_path boolean;
        CREATE INDEX IF NOT EXISTS apis_path ON apis(path);
      ]]
    end,

    down = function(options)
      return [[
        DROP INDEX apis_path;
        ALTER TABLE apis DROP path;
        ALTER TABLE apis DROP strip_path;
      ]]
    end
  },

  -- 0.4.0 migrations
  {
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
}

return Migrations
