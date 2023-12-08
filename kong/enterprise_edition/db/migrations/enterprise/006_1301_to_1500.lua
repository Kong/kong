-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local openssl_x509  = require "resty.openssl.x509"
local str           = require "resty.string"

local function pg_delete_we_orphan(entity)
  return [[
    DO $$
    BEGIN
      DELETE FROM workspace_entities WHERE entity_id IN (
        SELECT entity_id FROM (
          SELECT * from workspace_entities WHERE entity_type=']] .. entity .. [['
        ) t1 LEFT JOIN ]] .. entity .. [[ t2
        ON t2.id::text = t1.entity_id
        WHERE t2.id IS NULL
      );
    EXCEPTION WHEN UNDEFINED_TABLE THEN
      -- Do nothing, accept existing state
    END$$;
  ]]
end

local function pg_fix_we_counters(entity)
  return [[
    UPDATE workspace_entity_counters AS wec
      SET count = we.count FROM (
        SELECT d.workspace_id AS workspace_id,
               d.entity_type AS entity_type,
               coalesce(c.count, 0) AS count
        FROM (
          SELECT id AS workspace_id, ']] .. entity .. [['::text AS entity_type
          FROM workspaces
        ) AS d LEFT JOIN (
        SELECT workspace_id, entity_type, COUNT(DISTINCT entity_id)
          FROM workspace_entities
          WHERE entity_type = ']] .. entity .. [['
          GROUP BY workspace_id, entity_type
        ) c
        ON d.workspace_id = c.workspace_id
      ) AS we
    WHERE wec.workspace_id = we.workspace_id
    AND wec.entity_type = we.entity_type;
  ]]
end

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

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS applications (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        name text,
        description text,
        redirect_uri text,
        meta text,
        developer_id uuid references developers (id) on delete cascade,
        consumer_id  uuid references consumers (id) on delete cascade,
        PRIMARY KEY(id)
      );

      CREATE INDEX IF NOT EXISTS applications_developer_id_idx ON applications(developer_id);

      CREATE TABLE IF NOT EXISTS application_instances (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        status int,
        service_id uuid references services (id) on delete cascade,
        application_id  uuid references applications (id) on delete cascade,
        composite_id text unique,
        suspended boolean NOT NULL,
        PRIMARY KEY(id)
      );

      CREATE TABLE IF NOT EXISTS document_objects (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        service_id uuid references services (id) on delete cascade,
        path text unique,
        PRIMARY KEY(id)
      );

      -- XXX: EE keep run_on for now
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "plugins" ADD "run_on" TEXT;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END;
      $$;

      CREATE TABLE IF NOT EXISTS "event_hooks" (
        "id"           UUID                         UNIQUE,
        "created_at"   TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        "source"       TEXT NOT NULL,
        "event"        TEXT,
        "handler"      TEXT NOT NULL,
        "on_change"    BOOLEAN,
        "snooze"       INTEGER,
        "config"       JSON                         NOT NULL
      );

      -- add `license_creation_date` field for license_data table
      DO $$
        BEGIN
          ALTER TABLE license_data ADD COLUMN license_creation_date TIMESTAMP;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;

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
      -- XXX: EE keep run_on for now
      -- We run both on up and teardown because of two possible conditions:
      --    - upgrade from kong CE: run_on gets _was_ deleted on teardown.
      --                            We run mig. up on new kong-ee, no run_on
      --                            column added, so it fails to start.
      --                            That's why we want it on up.
      --
      --    - upgrade from kong EE: run_on gets deleted on teardown by CE mig,
      --                            so up migration does not do anything since
      --                            it's already there.
      --                            That's why we want it on teardown
      assert(connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" ADD "run_on" TEXT;
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
        $$;
      ]]))

      -- List of entities that are workspaceable and have ttl
      local entities = {
        "keyauth_credentials",
        "oauth2_tokens",
        "oauth2_authorization_codes",
      }

      for _, entity in ipairs(entities) do
        -- delete orphan workspace_entities
        assert(connector:query(pg_delete_we_orphan(entity)))
        -- re-do workspace_entity_counters
        assert(connector:query(pg_fix_we_counters(entity)))
      end

      -- add `cert_digest` field for `ca_certificates` table
      pg_ca_certificates_migration(connector)
    end,
  },
}
