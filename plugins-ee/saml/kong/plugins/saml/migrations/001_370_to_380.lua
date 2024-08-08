-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


-- This migration updates plugin's config by removing timeout field as it's been deprecated (it then populates read_timeout, send_timeout and connect_timeout if they're not set)

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      UPDATE plugins
      SET config =
        jsonb_set(
          config,
          '{redis}',
          jsonb_build_object(
            'prefix',                   COALESCE(config #> '{redis, prefix}', config -> 'session_redis_prefix'),
            'socket',                   COALESCE(config #> '{redis, socket}', config -> 'session_redis_socket'),
            'username',                 COALESCE(config #> '{redis, host}', config -> 'session_redis_username'),
            'password',                 COALESCE(config #> '{redis, password}', config -> 'session_redis_password'),
            'connect_timeout',          COALESCE(config #> '{redis, connect_timeout}', config -> 'session_redis_connect_timeout'),
            'read_timeout',             COALESCE(config #> '{redis, read_timeout}', config -> 'session_redis_read_timeout'),
            'send_timeout',             COALESCE(config #> '{redis, send_timeout}', config -> 'session_redis_send_timeout'),
            'ssl',                      COALESCE(config #> '{redis, ssl}', config -> 'session_redis_ssl'),
            'ssl_verify',               COALESCE(config #> '{redis, ssl_verify}', config -> 'session_redis_ssl_verify'),
            'server_name',              COALESCE(config #> '{redis, server_name}', config -> 'session_redis_server_name'),
            'cluster_max_redirections', COALESCE(config #> '{redis, cluster_max_redirections}', config -> 'session_redis_cluster_max_redirections')
          ) ||
          -- 'host' and 'port' can only be filled when 'cluster_nodes' are not set since those fields are mutually exclusive
          CASE
            WHEN COALESCE(config #>> '{redis, cluster_nodes}', config ->> 'session_redis_cluster_nodes') IS NULL THEN
              jsonb_build_object(
                'host',                     COALESCE(config #> '{redis, host}', config -> 'session_redis_host'),
                'port',                     COALESCE(config #> '{redis, port}', config -> 'session_redis_port')
              )
            ELSE jsonb_build_object(
              'cluster_nodes',            COALESCE(config #> '{redis, cluster_nodes}', config -> 'session_redis_cluster_nodes')
            )
          END
        )
      WHERE name = 'saml';
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
            - 'session_redis_prefix'
            - 'session_redis_socket'
            - 'session_redis_host'
            - 'session_redis_port'
            - 'session_redis_username'
            - 'session_redis_password'
            - 'session_redis_connect_timeout'
            - 'session_redis_read_timeout'
            - 'session_redis_send_timeout'
            - 'session_redis_ssl'
            - 'session_redis_ssl_verify'
            - 'session_redis_server_name'
            - 'session_redis_cluster_nodes'
            - 'session_redis_cluster_max_redirections'
            - 'session_redis_cluster_maxredirections'
        WHERE name = 'saml';
        EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
          -- Do nothing, accept existing state
        END$$;
      ]]
      assert(connector:query(sql))
      return true
    end,
  },
}
