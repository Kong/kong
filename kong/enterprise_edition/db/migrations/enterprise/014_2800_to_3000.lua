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
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "ordering" jsonb;
        EXCEPTION WHEN DUPLICATE_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;

        CREATE TABLE IF NOT EXISTS keyring_keys (
            id text PRIMARY KEY,
            recovery_key_id text not null,
            key_encrypted text not null,
            created_at timestamp with time zone not null,
            updated_at timestamp with time zone not null
        );
      ]],
      teardown = function(connector)
        local _, err = connector:query("UPDATE plugins SET name = 'statsd' WHERE name = 'statsd-advanced'")
        if err then
          return nil, err
        end

        local _, err = connector:query("DELETE FROM plugins WHERE name = 'collector'")
        if err then
          return nil, err
        end

        return true
      end,
    },

    cassandra = {
      up = [[
        ALTER TABLE plugins ADD ordering TEXT;

        CREATE TABLE IF NOT EXISTS keyring_keys (
            id                  text PRIMARY KEY,
            recovery_key_id     text,
            key_encrypted       text,
            created_at          timestamp,
            updated_at          timestamp
          );
      ]],
      teardown = function(connector)
        local coordinator = assert(connector:get_stored_connection())
        local cassandra = require "cassandra"
        for rows, err in coordinator:iterate("SELECT id, name FROM plugins WHERE name = 'statsd-advanced'") do
          if err then
            return nil, err
          end

          for i = 1, #rows do
            local plugin = rows[i]
            local _, err = coordinator:execute("UPDATE plugins SET name = 'statsd' WHERE id = ?",
              { cassandra.uuid(plugin.id) })
            if err then
              return nil, err
            end
          end
        end

        for rows, err in coordinator:iterate("SELECT id, name FROM plugins WHERE name = 'collector'") do
          if err then
            return nil, err
          end

          for i = 1, #rows do
            local plugin = rows[i]
            local _, err = coordinator:execute("DELETE FROM plugins WHERE id = ?",
              { cassandra.uuid(plugin.id) })
            if err then
              return nil, err
            end
          end
        end

        return true
      end
    },
}
