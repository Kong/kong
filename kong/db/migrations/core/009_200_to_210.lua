local operations = require "kong.db.migrations.operations.200_to_210"

local fmt           = string.format
local openssl_x509  = require "resty.openssl.x509"
local str           = require "resty.string"

local function pg_ca_certificates_migration(connector)
  assert(connector:connect_migrations())

  for ca_cert, err in connector:iterate('SELECT * FROM ca_certificates') do
    if err then
      return nil, err
    end

    local digest = str.to_hex(openssl_x509.new(ca_cert.cert):digest("sha256"))
    if not digest then
      return nil, "cannot create digest value of certificate with id: " .. ca_cert.id
    end

    local sql = string.format([[
          UPDATE ca_certificates SET cert_digest = '%s' WHERE id = '%s';
        ]], digest, ca_cert.id)

    assert(connector:query(sql))
  end

  assert(connector:query('ALTER TABLE ca_certificates ALTER COLUMN cert_digest SET NOT NULL'))
end

local function c_ca_certificates_migration(connector)
  local coordinator = connector:connect_migrations()

  for rows, err in coordinator:iterate("SELECT cert, id FROM ca_certificates") do
    if err then
      return nil, err
    end

    for _, ca_cert in ipairs(rows) do
      local digest = str.to_hex(openssl_x509.new(ca_cert.cert):digest("sha256"))
      if not digest then
        return nil, "cannot create digest value of certificate with id: " .. ca_cert.id
      end

      _, err = connector:query(
        fmt("UPDATE ca_certificates SET cert_digest = '%s' WHERE partition = 'ca_certificates' AND id = %s",
          digest, ca_cert.id)
      )
      if err then
        return nil, err
      end
    end
  end
end


local core_entities = {
  {
    name = "upstreams",
    primary_key = "id",
    uniques = {"name"},
    fks = {},
  }, {
    name = "targets",
    primary_key = "id",
    uniques = {},
    fks = {{name = "upstream", reference = "upstreams", on_delete = "cascade"}},
  }, {
    name = "consumers",
    primary_key = "id",
    uniques = {"username", "custom_id"},
    fks = {},
  }, {
    name = "certificates",
    primary_key = "id",
    uniques = {},
    fks = {},
    partitioned = true,
  }, {
    name = "snis",
    primary_key = "id",
    -- do not convert "name" because it is unique_across_ws
    uniques = {},
    fks = {{name = "certificate", reference = "certificates"}},
    partitioned = true,
  }, {
    name = "services",
    primary_key = "id",
    uniques = {"name"},
    fks = {{name = "client_certificate", reference = "certificates"}},
    partitioned = true,
  }, {
    name = "routes",
    primary_key = "id",
    uniques = {"name"},
    fks = {{name = "service", reference = "services"}},
    partitioned = true,
  }, {
    name = "plugins",
    cache_key = { "name", "route", "service", "consumer" },
    primary_key = "id",
    uniques = {},
    fks = {{name = "route", reference = "routes", on_delete = "cascade"}, {name = "service", reference = "services", on_delete = "cascade"}, {name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}


--------------------------------------------------------------------------------
-- High-level description of the migrations to execute on 'up'
-- @param ops table: table of functions which execute the low-level operations
-- for the database (each function returns a string).
-- @return SQL or CQL
local function ws_migration_up(ops)
  return ops:ws_add_workspaces()
      .. ops:ws_adjust_fields(core_entities)
end


--------------------------------------------------------------------------------
-- High-level description of the migrations to execute on 'teardown'
-- @param ops table: table of functions which execute the low-level operations
-- for the database (each function receives a connector).
-- @return a function that receives a connector
local function ws_migration_teardown(ops)
  return function(connector)
    ops:ws_adjust_data(connector, core_entities)
  end
end


--------------------------------------------------------------------------------


return {
  postgres = {
    up = [[
        -- ca_certificates table
        ALTER TABLE ca_certificates DROP CONSTRAINT IF EXISTS ca_certificates_cert_key;

        DO $$
          BEGIN
            ALTER TABLE ca_certificates ADD COLUMN "cert_digest" TEXT UNIQUE;
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;

        DO $$
          BEGIN
            ALTER TABLE services ADD COLUMN "tls_verify" BOOLEAN NOT NULL;
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;

        DO $$
          BEGIN
            ALTER TABLE services ADD COLUMN "tls_verify_depth" SMALLINT;
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;

        DO $$
          BEGIN
            ALTER TABLE services ADD COLUMN "ca_certificates" TEXT[];
          EXCEPTION WHEN duplicate_column THEN
            -- Do nothing, accept existing state
          END;
        $$;
    ]] .. ws_migration_up(operations.postgres.up),

    teardown = function(connector)
      ws_migration_teardown(operations.postgres.teardown)(connector)

      -- add `cert_digest` field for `ca_certificates` table
      pg_ca_certificates_migration(connector)
    end
  },
  cassandra = {
    up = [[
      -- ca_certificates
      ALTER TABLE ca_certificates ADD cert_digest text;

      DROP INDEX IF EXISTS ca_certificates_cert_idx;
      CREATE INDEX IF NOT EXISTS ca_certificates_cert_digest_idx ON ca_certificates(cert_digest);

      ALTER TABLE services ADD tls_verify boolean;
      ALTER TABLE services ADD tls_verify_depth int;
      ALTER TABLE services ADD ca_certificates set<text>;
    ]] .. ws_migration_up(operations.cassandra.up),

    teardown = function(connector)
      ws_migration_teardown(operations.cassandra.teardown)(connector)

      -- add `cert_digest` field for `ca_certificates` table
      c_ca_certificates_migration(connector)
    end
  }
}
