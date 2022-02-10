-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    teardown = function(connector)
      local _, err = connector:query([[
        DELETE FROM workspace_entity_counters
              WHERE entity_type = 'oauth2_tokens';
      ]])

      return err == nil, err
    end,
  },

  cassandra = {
    teardown = function(connector)
      local cassandra = require "cassandra"

      local workspaces = {}
      local coordinator = connector:connect_migrations()

      for res, err in coordinator:iterate("SELECT * FROM workspace_entity_counters") do
        if err then
          return nil, err
        end

        for _, row in ipairs(res) do
          if row.entity_type == "oauth2_tokens" then
            table.insert(workspaces, row.workspace_id)
          end
        end
      end

      for _, ws_id in ipairs(workspaces) do
        local _, err = coordinator:execute(
          [[
            DELETE FROM workspace_entity_counters
                  WHERE entity_type = 'oauth2_tokens'
                    AND workspace_id = ?
          ]],
          { cassandra.uuid(ws_id) }
        )

        if err then
          return nil, err
        end
      end

      return true
    end,
  },
}
