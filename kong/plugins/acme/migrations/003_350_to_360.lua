-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
    postgres = {
      up = [[
        DO $$
        BEGIN
          UPDATE plugins
          SET config =
            config
                #- '{storage_config,redis}'

            || jsonb_build_object(
                'storage_config',
                (config -> 'storage_config') - 'redis'
                || jsonb_build_object(
                  'redis',
                  jsonb_build_object(
                      'host', config #> '{storage_config, redis, host}',
                      'port', config #> '{storage_config, redis, port}',
                      'password', config #> '{storage_config, redis, auth}',
                      'username', config #> '{storage_config, redis, username}',
                      'ssl', config #> '{storage_config, redis, ssl}',
                      'ssl_verify', config #> '{storage_config, redis, ssl_verify}',
                      'server_name', config #> '{storage_config, redis, ssl_server_name}',
                      'timeout', config #> '{storage_config, redis, timeout}',
                      'database', config #> '{storage_config, redis, database}'
                  ) || jsonb_build_object(
                      'extra_options',
                      jsonb_build_object(
                          'scan_count', config #> '{storage_config, redis, scan_count}',
                          'namespace', config #> '{storage_config, redis, namespace}'
                      )
                  )
                )
              )
            WHERE name = 'acme';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
      ]],
    },
}
