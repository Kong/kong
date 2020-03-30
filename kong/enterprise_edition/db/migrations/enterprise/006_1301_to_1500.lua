local cassandra = require "cassandra"

local function pg_delete_we_orphan(entity)
  return [[
    DELETE FROM workspace_entities WHERE entity_id IN (
      SELECT entity_id FROM (
        SELECT * from workspace_entities WHERE entity_type=']] .. entity .. [['
      ) t1 LEFT JOIN ]] .. entity .. [[ t2
      ON t2.id::text = t1.entity_id
      WHERE t2.id IS NULL
    );
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

local function c_migrate_license_data(connector)
  -- migrate `license_data` from the old table to a new one
  local res, err = connector:query([[ SELECT * FROM license_data LIMIT 1; ]])

  if not err and not res.license_creation_date then
    local coordinator = connector:connect_migrations()
    local cluster = connector.cluster;
    for rows, err in coordinator:iterate("SELECT * FROM license_data") do
      if err then
        return nil, err
      end

      for _, row in ipairs(rows) do
        assert(cluster:execute("UPDATE license_data_tmp SET req_cnt = req_cnt + ? WHERE node_id = ?",
          {
            cassandra.counter(row.req_cnt),
            cassandra.uuid(row.node_id)
          }))
      end
    end

    -- drop table
    assert(connector:query([[
          DROP TABLE IF EXISTS license_data;
        ]]))

    -- recreate table with the new field
    assert(connector:query([[
          /* License data */
          CREATE TABLE IF NOT EXISTS license_data (
            node_id                 uuid,
            license_creation_date   timestamp,
            req_cnt                 counter,
            PRIMARY KEY (node_id, license_creation_date)
          );
        ]]))

    -- copy data from temp table to a new one
    for rows, err in coordinator:iterate("SELECT * FROM license_data_tmp") do
      if err then
        return nil, err
      end

      -- add current timestamp for old data which didn't have license creation date info
      local date = os.time() * 1000
      for _, row in ipairs(rows) do
        assert(cluster:execute(
          "UPDATE license_data SET req_cnt = req_cnt + ? WHERE node_id = ? AND license_creation_date = ?",
          {
            cassandra.counter(row.req_cnt),
            cassandra.uuid(row.node_id),
            cassandra.timestamp(date),
          }))
      end
    end

    -- drop temp table
    assert(connector:query([[
          DROP TABLE IF EXISTS license_data_tmp;
        ]]))
  end
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
    end,
  },

  cassandra = {
    up = [[
      -- XXX: EE keep run_on for now
      ALTER TABLE plugins ADD run_on TEXT;

      /* Add temporary table for license data table */
      CREATE TABLE IF NOT EXISTS license_data_tmp (
        node_id         uuid,
        req_cnt         counter,
        PRIMARY KEY (node_id)
      );

      CREATE TABLE IF NOT EXISTS applications (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        name text,
        description text,
        redirect_uri text,
        meta text,
        developer_id uuid,
        consumer_id  uuid,
        PRIMARY KEY(id)
      );

      CREATE INDEX IF NOT EXISTS applications_developer_id_idx ON applications(developer_id);
      CREATE INDEX IF NOT EXISTS applications_consumer_id_idx ON applications(consumer_id);

      CREATE TABLE IF NOT EXISTS application_instances (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        status int,
        service_id uuid,
        application_id uuid,
        composite_id text,
        suspended boolean,
        PRIMARY KEY(id)
      );

      CREATE INDEX IF NOT EXISTS application_instances_composite_id_idx ON application_instances(composite_id);
      CREATE INDEX IF NOT EXISTS application_instances_service_id_idx ON application_instances(service_id);
      CREATE INDEX IF NOT EXISTS application_instances_application_id_idx ON application_instances(application_id);

      CREATE TABLE IF NOT EXISTS event_hooks (
        id             uuid PRIMARY KEY,
        created_at     timestamp,
        source         text,
        event          text,
        handler        text,
        on_change      boolean,
        snooze         int,
        config         text
      );

      CREATE TABLE IF NOT EXISTS document_objects (
        id          uuid,
        created_at  timestamp,
        updated_at  timestamp,
        service_id uuid,
        path text,
        PRIMARY KEY(id)
      );

      CREATE INDEX IF NOT EXISTS document_objects_path_idx ON document_objects(path);
      CREATE INDEX IF NOT EXISTS document_objects_service_id_idx ON document_objects(service_id);
    ]],
    teardown = function(connector)
      -- XXX: EE keep run_on for now, ignore error
      connector:query([[
        ALTER TABLE plugins ADD run_on TEXT;
      ]])

      c_migrate_license_data(connector)
    end,
  }
}
