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
    ]],
    teardown = function(connector)
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
    ]],
    teardown = function(connector)
      -- add `cert_digest` field for `ca_certificates` table
      c_ca_certificates_migration(connector)
    end
  }
}
