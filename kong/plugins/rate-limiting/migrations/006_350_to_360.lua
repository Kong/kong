return {
    postgres = {
      up = [[
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
            || jsonb_build_object(
                'redis',
                jsonb_build_object(
                    'host', config->'redis_host',
                    'port', config->'redis_port',
                    'password', config->'redis_password',
                    'username', config->'redis_username',
                    'ssl', config->'redis_ssl',
                    'ssl_verify', config->'redis_ssl_verify',
                    'server_name', config->'redis_server_name',
                    'timeout', config->'redis_timeout',
                    'database', config->'redis_database'
                )
            )
            WHERE name = 'rate-limiting';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
      ]],
    },
}
