local cassandra   = require "cassandra"
local cjson       = require "cjson.safe"
local floor       = math.floor
local re_match    = ngx.re.match
local str_format  = string.format
local timestamp   = require "kong.tools.timestamp"
local uuid        = require "kong.tools.utils".uuid

local function get_new_cache_key(current_cache_key)
  local new_cache_key
  if current_cache_key ~= nil then
    local captures = re_match(current_cache_key, [[plugins\:proxy-cache(.*)$]],
                              "o")
    if captures ~= nil then
      new_cache_key = "plugins:proxy-cache-advanced" .. captures[1]
    end
  end
  return new_cache_key
end

local function cassandra_uuid_or_unset(uuid_from_cs)
  return uuid_from_cs and cassandra.uuid(uuid_from_cs) or cassandra.unset
end

return {
  postgres = {
    up = [[]],
    teardown = function(connector)
      local function escape_literal(value)
        if value == ngx.null then
          return "NULL"
        end

        return connector:escape_literal(value)
      end

      assert(connector:connect_migrations())
      local select_query = [[
        SELECT * FROM plugins
        WHERE name = 'proxy-cache'
      ]]

      for plugin, err in connector:iterate(select_query) do
        local new_id = escape_literal(uuid())
        local new_name = escape_literal("proxy-cache-advanced")
        local new_cache_key = get_new_cache_key(plugin.cache_key or ngx.null)
        local api_id = escape_literal(plugin.api_id or ngx.null)
        local consumer_id = escape_literal(plugin.consumer_id or ngx.null)
        local service_id = escape_literal(plugin.service_id or ngx.null)
        local route_id = escape_literal(plugin.route_id or ngx.null)
        local run_on = escape_literal(plugin.run_on or ngx.null)
        local enabled = escape_literal(plugin.enabled or ngx.null)
        local config, err = cjson.encode(plugin.config)
        if err then
          return nil, err
        end
        new_cache_key = escape_literal(new_cache_key)
        config = escape_literal(config)

        -- insert new plugin entity
        local insert_query = str_format([[
          INSERT INTO plugins(id, cache_key, name, consumer_id, service_id,
                              route_id, api_id, config, enabled, run_on)
          VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
        ]], new_id, new_cache_key, new_name, consumer_id, service_id, route_id,
            api_id, config, enabled, run_on)
        local _, err = connector:query(insert_query)
        if err then
          return nil, err
        end

        -- delete old plugin entity
        local delete_query = str_format([[
          DELETE FROM plugins
          WHERE id = %s;
        ]], escape_literal(plugin.id))
        local _, err = connector:query(delete_query)
        if err then
          return nil, err
        end

        -- update workspace entities
        local entity_select_query = str_format([[
          SELECT * FROM workspace_entities
          WHERE entity_id = %s
        ]], escape_literal(plugin.id))

        for entity, err in connector:iterate(entity_select_query) do
          local new_ent_ws_id = escape_literal(entity.workspace_id)
          local new_ent_ws_name = escape_literal(entity.workspace_name)

          -- insert new workspace entity
          local insert_entity_query = str_format([[
            INSERT INTO workspace_entities(workspace_id, workspace_name,
                                          entity_id, entity_type,
                                          unique_field_name, unique_field_value)
            VALUES(%s, %s, %s, %s, %s, %s);
          ]], new_ent_ws_id, new_ent_ws_name, new_id, escape_literal("plugins"),
              escape_literal("id"), new_id)
          local _, err = connector:query(insert_entity_query)
          if err then
            return nil, err
          end
        end

        -- delete old workspace entities
        local delete_entity_query = str_format([[
          DELETE FROM workspace_entities
          WHERE entity_id = %s
        ]], escape_literal(plugin.id))
        local _, err = connector:query(delete_entity_query)
        if err then
          return nil, err
        end

        -- update rbac
        local update_rbac_query = str_format([[
          UPDATE rbac_role_entities SET entity_id = %s
          WHERE entity_type = "plugins" AND entity_id = %s
        ]], new_id, escape_literal(plugin.id))
        local _, err = connector:query(update_rbac_query)
        if err then
          return nil, err
        end

      end
    end,
  },

  cassandra = {
    up = [[]],
    teardown = function(connector)
      assert(connector:connect_migrations())
      local select_query = [[
        SELECT * FROM plugins
        WHERE name = 'proxy-cache'
      ]]
      local insert_query = [[
        INSERT INTO plugins(id, created_at, cache_key, name, consumer_id,
                            service_id, route_id, api_id, config, enabled,
                            run_on)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ]]
      local delete_query = [[
        DELETE FROM plugins
        WHERE id = ?
      ]]
      local workspaces_select_query = [[
        SELECT id FROM workspaces
      ]]

      local coordinator = connector:connect_migrations()

      for rows, err in coordinator:iterate(select_query) do
        if err then
          return err
        end

        for _, plugin in ipairs(rows) do
          local config, err = cjson.decode(plugin.config)
          if err then
            return err
          end

          local new_id = cassandra.uuid(uuid())
          local new_created_at = cassandra.timestamp(floor(timestamp.get_utc_ms()))
          local new_name = "proxy-cache-advanced"
          local new_cache_key = get_new_cache_key(plugin.cache_key) or cassandra.unset
          local api_id = cassandra_uuid_or_unset(plugin.api_id)
          local consumer_id = cassandra_uuid_or_unset(plugin.consumer_id)
          local service_id = cassandra_uuid_or_unset(plugin.service_id)
          local route_id = cassandra_uuid_or_unset(plugin.route_id)
          local run_on = plugin.run_on or cassandra.unset
          local enabled = plugin.enabled or cassandra.unset
          local config, err = cjson.encode(config)
          if err then
            return nil, err
          end

          -- insert new plugin entity
          local _, err = coordinator:execute(insert_query, {new_id,
                                        new_created_at, new_cache_key,
                                        new_name, consumer_id, service_id,
                                        route_id, api_id, config, enabled,
                                        run_on})
          if err then
            return nil, err
          end

          -- delete old plugin entity
          local _, err = coordinator:execute(delete_query,
                                            {cassandra.uuid(plugin.id)})
          if err then
            return nil, err
          end

          -- update workspace entities
          for ws_rows, err in coordinator:iterate(workspaces_select_query) do
            if err then
              return nil, err
            end

            for _, workspace in ipairs(ws_rows) do
              local entity_select_query = str_format([[
                SELECT * FROM workspace_entities
                WHERE workspace_id = %s AND
                entity_id = '%s' AND
                unique_field_name = 'id'
              ]], workspace.id, plugin.id)
              for ent_rows, err in coordinator:iterate(entity_select_query) do
                if err then
                  return nil, err
                end

                for _, entity in ipairs(ent_rows) do
                  -- insert new workspace entity
                  local insert_entity_query = str_format([[
                    INSERT INTO workspace_entities(workspace_id, workspace_name,
                                                  entity_id, entity_type,
                                                  unique_field_name,
                                                  unique_field_value)
                    VALUES(%s, '%s', '%s', 'plugins', 'id', '%s');
                  ]], entity.workspace_id, entity.workspace_name, new_id.val,
                    new_id.val)
                  local _, err = coordinator:execute(insert_entity_query)
                  if err then
                    return nil, err
                  end

                  -- delete old workspace entity
                  local delete_entity_query = str_format([[
                    DELETE FROM workspace_entities
                    WHERE workspace_id = %s AND
                    entity_id = '%s' AND
                    unique_field_name = 'id'
                  ]], workspace.id, plugin.id)
                  local _, err = coordinator:execute(delete_entity_query)
                  if err then
                    return nil, err
                  end

                end
              end
            end
          end

          local select_all_roles = [[
            SELECT * FROM rbac_roles
          ]]

          for page, err in coordinator:iterate(select_all_roles) do
            if err then
              return nil, err
            end

            for _, role in ipairs(page) do
              local select_rbac_role_entities = str_format([[
                SELECT * FROM rbac_role_entities
                WHERE entity_id = '%s' AND role_id = %s
              ]], plugin.id, role.id)

              for page, err in coordinator:iterate(select_rbac_role_entities) do
                if err then
                  return nil, err
                end
                for _, row in ipairs(page) do
                  local insert_rbac_role_entity = [[
                    INSERT INTO rbac_role_entities(role_id, entity_id,
                                                   actions, comment,
                                                   created_at,
                                                   entity_type, negative)
                    VALUES(?, ?, ?, ?, ?, ?, ?)
                  ]]
                  local _, err = coordinator:execute(insert_rbac_role_entity, {
                    connector:escape(role.id, "uuid"),
                    connector:escape(new_id.val, "string"),
                    connector:escape(row.actions, "integer"),
                    connector:escape(row.comment, "string"),
                    connector:escape(ngx.now(), "timestamp"),
                    connector:escape(row.entity_type, "string"),
                    connector:escape(row.negative, "boolean"),
                  })
                  if err then
                    return nil, err
                  end

                  local delete_rbac_role_entity = str_format([[
                    DELETE FROM rbac_role_entities
                    WHERE role_id = %s AND entity_id = '%s'
                  ]], role.id, plugin.id)
                  local _, err = coordinator:execute(delete_rbac_role_entity)
                  if err then
                    return nil, err
                  end
                end
              end
            end
          end
        end
      end
    end,
  },
}

