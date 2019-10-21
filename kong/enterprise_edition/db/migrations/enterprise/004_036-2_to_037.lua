local fmt = string.format

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE developers ADD rbac_user_id uuid;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      CREATE INDEX IF NOT EXISTS developers_rbac_user_id_idx ON developers(rbac_user_id);

      -- Groups Entity
      CREATE TABLE IF NOT EXISTS groups (
        id          uuid,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        name text unique,
        comment text,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS groups_name_idx ON groups(name);

      -- Group and RBAC_Role Mapping
      CREATE TABLE IF NOT EXISTS group_rbac_roles(
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        group_id uuid REFERENCES groups (id) ON DELETE CASCADE,
        rbac_role_id uuid REFERENCES rbac_roles (id) ON DELETE CASCADE,
        workspace_id uuid REFERENCES workspaces (id) ON DELETE CASCADE,
        PRIMARY KEY (group_id, rbac_role_id)
      );

      -- Login Attempts
      CREATE TABLE IF NOT EXISTS login_attempts (
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        attempts json DEFAULT '{}'::json,
        ttl         TIMESTAMP WITH TIME ZONE,
        created_at  TIMESTAMP WITHOUT TIME ZONE  DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'UTC'),
        PRIMARY KEY (consumer_id)
      );

      -- Backport keyauth ttl, this will come on 1.4.0
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "keyauth_credentials" ADD "ttl" TIMESTAMP WITH TIME ZONE;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS keyauth_credentials_ttl_idx ON keyauth_credentials (ttl);
      EXCEPTION WHEN UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      -- Backport oauth2 ttl index, this will come in 1.4.0
      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS oauth2_authorization_codes_ttl_idx ON oauth2_authorization_codes (ttl);
      EXCEPTION WHEN UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;

      DO $$
      BEGIN
        CREATE INDEX IF NOT EXISTS oauth2_tokens_ttl_idx ON oauth2_tokens (ttl);
      EXCEPTION WHEN UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
    teardown = function(connector)
      assert(connector:connect_migrations())

      -- update old files workspace_entities.entity_type to 'legacy_files'
      -- rename files to legacy_files
      -- make new files table
      assert(connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS files
            RENAME TO legacy_files;
        EXCEPTION WHEN DUPLICATE_TABLE THEN
          -- Do nothing, accept existing state
        END;
        $$;

        DO $$
        BEGIN
          ALTER INDEX IF EXISTS "portal_files_name_idx" RENAME TO "legacy_files_name_idx";
        EXCEPTION WHEN DUPLICATE_TABLE THEN
          -- Do nothing, accept existing state
        END;
        $$;

        UPDATE workspace_entities SET entity_type='legacy_files' WHERE entity_type='files';

        CREATE TABLE IF NOT EXISTS files(
          id uuid PRIMARY KEY,
          path text UNIQUE NOT NULL,
          checksum text,
          contents text,
          created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
        );

        CREATE INDEX IF NOT EXISTS files_path_idx on files(path);
      ]]))
    end
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS legacy_files(
        id uuid PRIMARY KEY,
        auth boolean,
        name text,
        type text,
        contents text,
        created_at timestamp
      );

      CREATE INDEX IF NOT EXISTS ON legacy_files(name);
      CREATE INDEX IF NOT EXISTS ON legacy_files(type);

      ALTER TABLE developers ADD rbac_user_id uuid;
      CREATE INDEX IF NOT EXISTS ON developers(rbac_user_id);

      /* Groups Entity */
      CREATE TABLE IF NOT EXISTS groups (
        id          uuid,
        created_at  timestamp,
        name   text,
        comment  text,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS groups_name_idx ON groups(name);

      /* Group and RBAC_Role Mapping */
      CREATE TABLE IF NOT EXISTS group_rbac_roles(
        created_at timestamp,
        group_id uuid,
        rbac_role_id uuid,
        workspace_id uuid,
        PRIMARY KEY (group_id, rbac_role_id)
      );

      CREATE INDEX IF NOT EXISTS group_rbac_roles_rbac_role_id_idx ON group_rbac_roles(rbac_role_id);
      CREATE INDEX IF NOT EXISTS group_rbac_roles_workspace_id_idx ON group_rbac_roles(workspace_id);

      /* Login Attempts */
      CREATE TABLE IF NOT EXISTS login_attempts (
        consumer_id uuid,
        attempts map<text,int>,
        created_at  timestamp,
        PRIMARY KEY (consumer_id)
      );

    ]],
    teardown = function(connector, helpers)
      local coordinator = connector:connect_migrations()

      local _, err = connector:query([[ SELECT * FROM files LIMIT 1; ]])

      if not err then

        local files_def = {
          name    = "files",
          columns = {
            id         = "uuid",
            auth       = "boolean",
            name       = "text",
            type       = "text",
            contents   = "text",
            created_at = "timestamp",
          },
        }

        local legacy_files_def = {
          name    = "legacy_files",
          columns = {
            id         = "uuid",
            auth       = "boolean",
            name       = "text",
            type       = "text",
            contents   = "text",
            created_at = "timestamp",
          },
        }

        assert(helpers:copy_cassandra_records(files_def, legacy_files_def, {
            id         = "id",
            auth       = "auth",
            name       = "name",
            type       = "type",
            contents   = "contents",
            created_at = "created_at",
        }))

        local workspaces_map
        for rows, err in coordinator:iterate("select * from files") do
          for _, file in ipairs(rows) do
            if err then
              return nil, err
            end

            if not workspaces_map then
              workspaces_map = {}
              for rows, err in coordinator:iterate("select * from workspaces;") do
                if err then
                  return nil, err
                end

                for _, workspace in ipairs(rows) do
                  workspaces_map[workspace.id] = workspace
                end
              end
            end

            local workspace_entity

            for id, _ in pairs(workspaces_map) do
              local workspace_entities, err = connector:query(
                fmt("select * from workspace_entities where workspace_id = %s and entity_id = '%s' and unique_field_name = 'name';", id, file.id)
              )
              if err then
                return nil, err
              end

              workspace_entity = workspace_entities[1]
              if workspace_entity then
                break
              end
            end

            local workspace = workspace_entity and workspaces_map[workspace_entity.workspace_id]
            if not workspace then
              return nil, "not able to fetch workspace relation for file: " .. file.name
            end

            -- update files entity type to legacy_files for entity by name
            local _, err = connector:query(fmt("update workspace_entities set entity_type = 'legacy_files' " ..
              "where workspace_id = %s and entity_id = '%s' and unique_field_name = 'name';", workspace.id, file.id))
            if err then
              return nil, err
            end

            -- update files entity type to legacy_files for entity by id
            local _, err = connector:query(fmt("update workspace_entities set entity_type = 'legacy_files' " ..
              "where workspace_id = %s and entity_id = '%s' and unique_field_name = 'id';", workspace.id, file.id))
            if err then
              return nil, err
            end
          end
        end
      end

      assert(connector:query([[
        DROP INDEX IF EXISTS files_name_idx;
        DROP INDEX IF EXISTS files_type_idx;
        DROP TABLE IF EXISTS files;
      ]]))

      assert(connector:query([[
        CREATE TABLE IF NOT EXISTS files(
          id uuid PRIMARY KEY,
          path text,
          checksum text,
          contents text,
          created_at timestamp
        );

        CREATE INDEX IF NOT EXISTS ON files(path);
      ]]))
    end
  },
}
