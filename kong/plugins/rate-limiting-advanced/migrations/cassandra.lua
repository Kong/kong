local cjson = require "cjson.safe"


return {
  {
    name = "2018-03-26-120000_rename",
    up = function(_, _, dao)
      local coordinator, err = dao.db:get_coordinator()
      if not coordinator then
        return err
      end

      local cassandra = dao.db.cassandra
      local uuid = dao.db.dao_insert_values.id
      local timestamp = dao.db.dao_insert_values.timestamp

      local select_query = [[
        SELECT * FROM plugins WHERE name = 'rate-limiting'
      ]]
      local insert_query = [[
        INSERT INTO plugins(id, created_at, api_id, consumer_id, name, config, enabled)
        VALUES(?, ?, ?, ?, ?, ?, ?)
      ]]
      local delete_query = [[
        DELETE FROM plugins WHERE id = ? AND name = ?
      ]]

      for rows, err in coordinator:iterate(select_query) do
        if err then
          return err
        end

        for _, plugin in ipairs(rows) do
          local config, err = cjson.decode(plugin.config)
          if err then
            return err
          end

          -- look for something that looks like the ee plugin, using only
          -- fields marked 'required' in the plugin schema
          local is_ee = config.window_size and config.limit

          if is_ee then
            -- prepare values for new plugin entity
            local new_id = cassandra.uuid(uuid())
            local new_created_at = cassandra.timestamp(timestamp())
            local new_name = "rate-limiting-advanced"
            local api_id = plugin.api_id and cassandra.uuid(plugin.api_id) or cassandra.unset
            local consumer_id = plugin.consumer_id and cassandra.uuid(plugin.consumer_id) or cassandra.unset
            local config, err = cjson.encode(config)
            if err then
              return err
            end
            local enabled = plugin.enabled or cassandra.unset

            -- insert new plugin entity
            local _, err = dao.db:query(insert_query, {new_id, new_created_at, api_id,
              consumer_id, new_name, config, enabled})
            if err then
              return err
            end

            -- delete old plugin entity
            local _, err = dao.db:query(delete_query, {cassandra.uuid(plugin.id), "rate-limiting"})
            if err then
              return err
            end
          end
        end
      end
    end,
    down = function() end,
  },
}
