-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson       = require "cjson.safe"
local re_match    = ngx.re.match
local str_format  = string.format
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
          WHERE entity_type = 'plugins' AND entity_id = %s
        ]], new_id, escape_literal(plugin.id))
        local _, err = connector:query(update_rbac_query)
        if err then
          return nil, err
        end

      end
    end,
  },
}

