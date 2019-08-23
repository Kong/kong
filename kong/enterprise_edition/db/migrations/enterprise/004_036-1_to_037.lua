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
