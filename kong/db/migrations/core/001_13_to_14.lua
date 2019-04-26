local utils = require "kong.tools.utils"

local fmt = string.format

return {
  postgres = {
    up = [[
      -- 2018-03-27-123400_prepare_certs_and_snis
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ssl_certificates    RENAME TO certificates;
        ALTER TABLE IF EXISTS ssl_servers_names   RENAME TO snis;
      EXCEPTION WHEN duplicate_table THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE snis RENAME COLUMN ssl_certificate_id TO certificate_id;
        ALTER TABLE snis ADD    COLUMN id uuid;
      EXCEPTION WHEN undefined_column THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        ALTER TABLE snis ALTER COLUMN created_at TYPE timestamp with time zone
          USING created_at AT time zone 'UTC';
        ALTER TABLE certificates ALTER COLUMN created_at TYPE timestamp with time zone
          USING created_at AT time zone 'UTC';
      EXCEPTION WHEN undefined_column THEN
        -- Do nothing, accept existing state
      END$$;


      -- 2018-05-17-173100_hash_on_cookie
      DO $$
      BEGIN
        ALTER TABLE upstreams ADD hash_on_cookie text;
        ALTER TABLE upstreams ADD hash_on_cookie_path text;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END$$;

    ]],

    teardown = function(connector, helpers)
      assert(connector:connect_migrations())

      -- 2018-03-27-125400_fill_in_snis_ids
      local rows, err = connector:query([[
        SELECT * FROM snis;
      ]])
      if err then
        return err
      end
      local sql_buffer = { "BEGIN;" }
      local len = #rows
      for i = 1, len do
        sql_buffer[i + 1] = fmt("UPDATE snis SET id = '%s' WHERE name = '%s';",
                                utils.uuid(),
                                rows[i].name)
      end
      sql_buffer[len + 2] = "COMMIT;"
      assert(connector:query(table.concat(sql_buffer)))

      -- 2018-03-27-130400_make_ids_primary_keys_in_snis",
      assert(connector:query([[
        ALTER TABLE snis
          DROP CONSTRAINT IF EXISTS ssl_servers_names_pkey;

        ALTER TABLE snis
          DROP CONSTRAINT IF EXISTS ssl_servers_names_ssl_certificate_id_fkey;

        DO $$
        BEGIN
          ALTER TABLE snis
            ADD CONSTRAINT snis_name_unique UNIQUE(name);

          ALTER TABLE snis
            ADD PRIMARY KEY (id);

          ALTER TABLE snis
            ADD CONSTRAINT snis_certificate_id_fkey
            FOREIGN KEY (certificate_id)
            REFERENCES certificates;
        EXCEPTION WHEN duplicate_table THEN
          -- Do nothing, accept existing state
        END$$;
      ]]))
    end,
  },

  cassandra = {
    up = [[
      -- 2018-05-17-173100_hash_on_cookie
      ALTER TABLE upstreams ADD hash_on_cookie text;
      ALTER TABLE upstreams ADD hash_on_cookie_path text;
    ]],

    teardown = function(connector, helpers)

    end,
  },
}
