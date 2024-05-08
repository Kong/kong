return {
    postgres = {
      up = [[
        DO $$
        BEGIN
          UPDATE plugins
          SET config =
            config::jsonb
            || jsonb_build_object(
                'redis',
                jsonb_build_object(
                    'host', COALESCE(config->'redis_host', config #> '{redis, host}'),
                    'port', COALESCE(config->'redis_port', config #> '{redis, port}'),
                    'password', COALESCE(config->'redis_password', config #> '{redis, password}'),
                    'username', COALESCE(config->'redis_username', config #> '{redis, username}'),
                    'ssl', COALESCE(config->'redis_ssl', config #> '{redis, ssl}'),
                    'ssl_verify', COALESCE(config->'redis_ssl_verify', config #> '{redis, ssl_verify}'),
                    'server_name', COALESCE(config->'redis_server_name', config #> '{redis, server_name}'),
                    'timeout', COALESCE(config->'redis_timeout', config #> '{redis, timeout}'),
                    'database', COALESCE(config->'redis_database', config #> '{redis, database}')
                )
            )
            WHERE name = 'rate-limiting';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
      ]],
      teardown = function(connector, _)
        local sql = [[
          DO $$
          BEGIN
            UPDATE plugins
            SET config =
              config::jsonb
                - 'redis_host'
                - 'redis_port'
                - 'redis_password'
                - 'redis_username'
                - 'redis_ssl'
                - 'redis_ssl_verify'
                - 'redis_server_name'
                - 'redis_timeout'
                - 'redis_database'
            WHERE name = 'rate-limiting';
          EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
            -- Do nothing, accept existing state
          END$$;
        ]]
        assert(connector:query(sql))

        return true
      end,
    },
}
