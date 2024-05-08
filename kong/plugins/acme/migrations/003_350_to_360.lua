return {
    postgres = {
      up = [[
        DO $$
        BEGIN
          UPDATE plugins
          SET config =
              jsonb_set(
                config,
                '{storage_config,redis}',
                config #> '{storage_config, redis}'
                || jsonb_build_object(
                  'password', config #> '{storage_config, redis, auth}',
                  'server_name', config #> '{storage_config, redis, ssl_server_name}',
                  'extra_options', jsonb_build_object(
                    'scan_count', config #> '{storage_config, redis, scan_count}',
                    'namespace', config #> '{storage_config, redis, namespace}'
                  )
                )
              )
            WHERE name = 'acme';
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
              config
                #- '{storage_config,redis,auth}'
                #- '{storage_config,redis,ssl_server_name}'
                #- '{storage_config,redis,scan_count}'
                #- '{storage_config,redis,namespace}'
            WHERE name = 'acme';
          EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
            -- Do nothing, accept existing state
          END$$;
        ]]
        assert(connector:query(sql))
        return true
      end,
    },
}
