local cassandra = require "cassandra"
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
        return nil, err
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

      -- 2018-03-27-130400_make_ids_primary_keys_in_snis successfully covered
      -- in 000_base
    end,
  },

  cassandra = {
    up = [[
      -- 2018-03-22-141700_create_new_ssl_tables
      CREATE TABLE IF NOT EXISTS certificates(
        partition text,
        id uuid,
        cert text,
        key text,
        created_at timestamp,
        PRIMARY KEY (partition, id)
      );

      CREATE TABLE IF NOT EXISTS snis(
        partition text,
        id uuid,
        name text,
        certificate_id uuid,
        created_at timestamp,
        PRIMARY KEY (partition, id)
      );

      CREATE INDEX IF NOT EXISTS snis_name_idx ON snis(name);
      CREATE INDEX IF NOT EXISTS snis_certificate_id_idx ON snis(certificate_id);

      -- 2018-03-16-160000_index_consumers
      CREATE INDEX IF NOT EXISTS ON consumers(custom_id);
      CREATE INDEX IF NOT EXISTS ON consumers(username);

      -- 2018-05-17-173100_hash_on_cookie
      ALTER TABLE upstreams ADD hash_on_cookie text;
      ALTER TABLE upstreams ADD hash_on_cookie_path text;
    ]],

    teardown = function(connector, helpers)
      -- 2018-03-26-234600_copy_records_to_new_ssl_tables
      local _, err = connector:query([[ SELECT * FROM ssl_certificates LIMIT 1; ]])

      if not err then
        local ssl_certificates_def = {
          name    = "ssl_certificates",
          columns = {
            id         = "uuid",
            cert       = "text",
            key        = "text",
            created_at = "timestamp",
          },
          partition_keys = { "id" },
        }

        local certificates_def = {
          name    = "certificates",
          columns = {
            partition  = "text",
            id         = "uuid",
            cert       = "text",
            key        = "text",
            created_at = "timestamp",
          },
          partition_keys = { "partition", "id" },
        }

        assert(helpers:copy_cassandra_records(ssl_certificates_def, certificates_def, {
            partition  = function() return cassandra.text("certificates") end,
            id         = "id",
            cert       = "cert",
            key        = "key",
            created_at = "created_at",
        }))
      end

      local _, err = connector:query([[ SELECT * FROM ssl_servers_names LIMIT 1; ]])

      if not err then
        local ssl_servers_names_def = {
          name    = "ssl_servers_names",
          columns = {
            name       = "text",
            ssl_certificate_id = "uuid",
            created_at = "timestamp",
          },
          partition_keys = { "name", "ssl_certificate_id" },
        }

        local snis_def = {
          name    = "snis",
          columns = {
            partition      = "text",
            id             = "uuid",
            name           = "text",
            certificate_id = "uuid",
            created_at     = "timestamp",
          },
          partition_keys = { "partition", "id" },
        }

        assert(helpers:copy_cassandra_records(ssl_servers_names_def, snis_def, {
            partition      = function() return cassandra.text("snis") end,
            id             = function() return cassandra.uuid(utils.uuid()) end,
            name           = "name",
            certificate_id = "ssl_certificate_id",
            created_at     = "created_at",
        }))
      end

      -- 2018-03-27-002500_drop_old_ssl_tables
      assert(connector:query([[
        DROP INDEX IF EXISTS ssl_servers_names_ssl_certificate_id_idx;
        DROP TABLE IF EXISTS ssl_certificates;
        DROP TABLE IF EXISTS ssl_servers_names;
      ]]))
    end,
  },
}
