local fmt = string.format
local created_ts = math.floor(ngx.now()) * 1000

-- fixing snis implies:
-- for each sni in snis table
--   get its name
--   search its name in workspace_entities (it used to be the primary key). find the ws of it
--   update its name in the snis table for the prefixed workspace
--   add the id field to the workspace_entities table.
--   delete the old entry in workspace_entities
local function fix_snis_postgres(connector)
  connector:connect_migrations()
  for sni, err in connector:iterate("select * from snis") do
    if err then
      return nil, err
    end

    local rows, err = connector:query(
      fmt("select * from workspace_entities where entity_id='%s';",sni.name)
      )
    if err then
      return nil, err
    end

    local workspace_entity = rows[1]
    if not workspace_entity then
      return nil, "not able to fetch workspace relation for SNI: " .. sni.name
    end

    -- get workspace, just get first one
    local rows, err = connector:query(
      fmt("select * from workspaces where id = '%s';", workspace_entity.workspace_id)
    )
    if err then
      return nil, err
    end

    local workspace = rows[1]
    if not workspace then
      return nil, "not able to fetch workspace relation for SNI: " .. sni.name
    end

    -- insert unique fields (name, id) in workspace_entities
    local _, err = connector:query(fmt("insert into workspace_entities" ..
      "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
        " values('%s', '%s', '%s', 'snis', 'id', '%s');", workspace.name, workspace.id, sni.id, sni.id))
    if err then
      return nil, err
    end

    local _, err = connector:query(fmt("insert into workspace_entities" ..
      "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
        " values('%s', '%s', '%s', 'snis', 'name', '%s');", workspace.name, workspace.id, sni.id, sni.name))
    if err then
      return nil, err
    end

    --clean up old ssl_servers_names
    local _, err = connector:query(fmt("delete from workspace_entities where entity_id = '%s';", sni.name))
    if err then
      return nil, err
    end

    assert(connector:query([[
        DROP INDEX IF EXISTS ssl_servers_names_ssl_certificate_id_idx;
        DROP TABLE IF EXISTS ssl_servers_names;
        DROP TABLE IF EXISTS ssl_certificates;
      ]]))
  end
end

local function ws_as_map(coordinator)
  local workspaces_map = {}
  for rows, err in coordinator:iterate("select * from workspaces;") do
    if err then
      return nil, err
    end

    for _, workspace in ipairs(rows) do
      workspaces_map[workspace.id] = workspace
    end
  end
  return workspaces_map
end


return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        INSERT INTO certificates(id, created_at, cert, key)
          SELECT id, created_at, cert, key FROM ssl_certificates
       WHERE
          NOT EXISTS (
              SELECT id FROM certificates WHERE id = ssl_certificates.id
          );

        INSERT INTO snis(id, created_at, name, certificate_id)
          SELECT uuid_in(overlay(overlay(md5(random()::text || ':' || clock_timestamp()::text) placing '4' from 13) placing to_hex(floor(random()*(11-8+1) + 8)::int)::text from 17)::cstring),
                 created_at, name, ssl_certificate_id FROM ssl_servers_names
        WHERE
          NOT EXISTS (
              SELECT name FROM snis WHERE name = ssl_servers_names.name
          );

      EXCEPTION WHEN undefined_table THEN
        -- Do nothing, accept existing state
      END$$;

-- workspace entities entity_type
      UPDATE workspace_entities set entity_type='certificates' where entity_type='ssl_certificates';
      UPDATE workspace_entities set entity_type='snis' where entity_type='ssl_servers_names';


-- rbac_role_entities
      UPDATE rbac_role_entities SET entity_type='certificates' WHERE entity_type='ssl_certificates';
      UPDATE rbac_role_entities SET entity_type='snis' WHERE entity_type='ssl_servers_names';
      UPDATE rbac_role_entities SET entity_id = snis.id FROM snis WHERE rbac_role_entities.entity_id = snis.name;

    ]]
    ,

    teardown = function(connector)
      fix_snis_postgres(connector) -- step 3
    end
  },

    cassandra = {
      up = [[]],
      teardown = function(connector)

        local function fix_dupe_workspace_and_timestamp()
          -- delete extra default workspace if there are 2 default wss
          -- and fix timestamp if there's only 1
          local def_workspaces, err = connector:query("select * from workspaces where name = 'default'")
          if err then
            return nil, err
          end

          local ws_000, err = connector:query(
            "select * from workspaces where name = 'default' and id=00000000-0000-0000-0000-000000000000;")
          if err then
            return nil, err
          end
          if #ws_000 == 0 then
            return true
          end

          if #def_workspaces == 2 then
            -- if we have 2 default workspaces, and one has 0000...0000 id, we delete it FTI-701
            local _, err = connector:query("delete from workspaces where id=00000000-0000-0000-0000-000000000000;")
            if err then
              return nil, err
            end

          elseif #def_workspaces == 1 then
            -- if we have only one, we have to add the created_at timestamp FT-677
            assert(connector:query(
              fmt([[INSERT INTO workspaces(id, name, config, meta, created_at)
                  VALUES (00000000-0000-0000-0000-000000000000, 'default', '{"portal":true}', '{}', %s);]], created_ts)))
          end
        end



        local coordinator = connector:connect_migrations()

        -- delete extra default workspace if there are 2 default wss
        -- and fix timestamp if there's only 1
        local _, err = fix_dupe_workspace_and_timestamp()
        if err then
          return nil, err
        end

        -- update rbac_role_entities entity_type from ssl_certificates to certificates
        for rows, err in coordinator:iterate("select * from rbac_role_entities where entity_type = 'ssl_certificates'") do
          if err then
            return nil, err
          end

          for _, row in ipairs(rows) do
            local _, err = connector:query(
              fmt([[ UPDATE rbac_role_entities SET entity_type='certificates' WHERE role_id = %s and entity_id = '%s';]], row.role_id, row.entity_id)
            )
            if err then
              return nil, err
            end
          end
        end

        -- update rbac_role_entities entity_type from ssl_servers_names to snis and use id as entity_id
        for rows, err in coordinator:iterate("select * from rbac_role_entities where entity_type = 'ssl_servers_names'") do
          if err then
            return nil, err
          end

          for _, row in ipairs(rows) do
            local snis, err = connector:query(fmt("select * from snis where name = '%s'", row.entity_id))
            if err then
              return nil, err
            end
            local sni = snis[1]

            if not sni then
              return nil, "not able to fetch SNI: " .. row.entity_id
            end

            local _, err = connector:query(
              fmt([[ INSERT INTO rbac_role_entities (role_id, entity_id, entity_type, actions, negative, comment, created_at) VALUES (%s, '%s', 'snis', %s, %s, '%s', %s);]],
                row.role_id,
                sni.id,
                row.actions,
                row.negative,
                row.comment,
                row.created_at)
            )
            if err then
              return nil, err
            end
            local _, err = connector:query(
              fmt([[ DELETE from rbac_role_entities where role_id = %s and entity_id = '%s';]],
                row.role_id,
                row.entity_id
              )
            )
            if err then
              return nil, err
            end
          end
        end

        -- update workspace_entities entity_type from ssl_certificates to certificates
        for rows, err in coordinator:iterate("select * from workspace_entities where entity_type = 'ssl_certificates'") do
          if err then
            return nil, err
          end
          for _, row in ipairs(rows) do
            local _, err = connector:query(
              fmt([[ UPDATE workspace_entities SET entity_type='certificates' WHERE workspace_id = %s and entity_id = '%s' and unique_field_name = 'id' ;]], row.workspace_id, row.entity_id)
            )
            if err then
              return nil, err
            end
          end
        end

        local workspaces_map
        for rows, err in coordinator:iterate("select * from snis") do
          for _, sni in ipairs(rows) do
            if err then
              return nil, err
            end

            if not workspaces_map then
              local err
              workspaces_map, err = ws_as_map(coordinator)
              if err then
                return nil, err
              end
            end

            local workspace_entity
            for id, _ in pairs(workspaces_map) do
              local workspace_entities, err = connector:query(
                fmt("select * from workspace_entities where workspace_id = %s and entity_id = '%s' and unique_field_name = 'name';", id, sni.name)
              )
              if err then
                return nil, err
              end

              workspace_entity = workspace_entities[1]
              if workspace_entity then
                break
              end
            end

            if not workspace_entity then
              return nil, "not able to fetch workspace relation for SNI: " .. sni.name
            end

            -- get workspace, just get first one
            local workspace = workspaces_map[workspace_entity.workspace_id]
            if not workspace then
              return nil, "not able to fetch workspace for SNI: " .. sni.name
            end

            -- update name ws:name in snis table
           --[[ local _, err = connector:query(fmt("update snis set name = '%s:%s' where partition = 'snis' and id = %s;", workspace.name, sni.name, sni.id))
            if err then
              return nil, err
            end]]
            -- insert unique fields (name, id) in workspace_entities XXX is name still unique??
            local _, err = connector:query(fmt("insert into workspace_entities" ..
              "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
              " values('%s', %s, '%s', 'snis', 'id', '%s');", workspace.name, workspace.id, sni.id, sni.id))
            if err then
              return nil, err
            end

            local _, err = connector:query(fmt("insert into workspace_entities" ..
              "(workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)" ..
              " values('%s', %s, '%s', 'snis', 'name', '%s');", workspace.name, workspace.id, sni.id, sni.name))
            if err then
              return nil, err
            end

            --clean up old ssl_servers_name
            local _, err = connector:query(fmt("delete from workspace_entities where workspace_id = %s and entity_id = '%s' and unique_field_name = 'name';", workspace.id, sni.name))
            if err then
              return nil, err
            end
          end
        end
    end
  },
}
