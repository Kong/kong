local cjson = require "cjson.safe"


local function escape_literal(val)
  if val == ngx.null then
    return "NULL"
  end

  local t_val = type(val)
  if t_val == "number" then
    return tostring(val)
  elseif t_val == "string" then
    return "'" .. tostring((val:gsub("'", "''"))) .. "'"
  elseif t_val == "boolean" then
    return val and "TRUE" or "FALSE"
  end
  error("don't know how to escape value: " .. tostring(val))
end


return {
  {
    name = "2018-03-26-120000_rename",
    up = function(_, _, dao)
      local select_query = [[
        SELECT * FROM plugins WHERE name = 'rate-limiting'
      ]]
      local plugins, err = dao.db:query(select_query)
      if err then
        return err
      end

      local uuid = dao.db.dao_insert_values.id

      for i = 1, #plugins do
        local plugin = plugins[i]
        local config = plugin.config

        -- look for something that looks like the ee plugin, using only
        -- fields marked 'required' in the plugin schema
        local is_ee = config.window_size and config.limit

        if is_ee then
          -- prepare values for new plugin entity
          local new_id = escape_literal(uuid())
          local new_name = escape_literal("rate-limiting-advanced")
          local api_id = escape_literal(plugin.api_id or ngx.null)
          local consumer_id = escape_literal(plugin.consumer_id or ngx.null)
          local config, err = cjson.encode(config)
          if err then
            return err
          end
          config = escape_literal(config)
          local enabled = escape_literal(plugin.enabled or ngx.null)

          -- insert new plugin entity
          local insert_query = string.format([[
            INSERT INTO plugins(id, api_id, consumer_id, name, config, enabled)
              VALUES(%s, %s, %s, %s, %s, %s)
          ]], new_id, api_id, consumer_id, new_name, config, enabled)
          local _, err = dao.db:query(insert_query)
          if err then
            return err
          end
        end

        -- delete old plugin entity
        local delete_query = string.format([[
          DELETE FROM plugins WHERE id = %s AND name = %s
        ]], escape_literal(plugin.id), escape_literal("rate-limiting"))
        local _, err = dao.db:query(delete_query)
        if err then
          return err
        end
      end
    end,
    down = function() end,
  },
}
