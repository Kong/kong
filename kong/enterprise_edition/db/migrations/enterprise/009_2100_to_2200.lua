local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"
local log          = require "kong.cmd.utils.log"

local cassandra_table_is_partitioned = operations.utils.cassandra_table_is_partitioned
local render = operations.utils.render
local postgres_has_workspace_enitites = operations.utils.postgres_has_workspace_entities
local cassandra_has_workspace_enitites = operations.utils.cassandra_has_workspace_entities
--------------------------------------------------------------------------------

return {
  -- revert migration for:
  -- https://github.com/Kong/kong-ee/commit/64f56f079236336d55a4116e85e04e629357b87e

  postgres = {
    up = [[]],
    teardown = function (connector)
      if not postgres_has_workspace_enitites(nil, connector)[1] then
        return nil
      end

      local _, err = connector:query([[

        -- revert consumers ws_id from workspace_entities table

        UPDATE consumers
        SET ws_id = we.workspace_id
        FROM workspace_entities we
        WHERE entity_type='consumers'
          AND unique_field_name='id'
          AND unique_field_value=consumers.id::text;
      ]])

      if err then
        log.debug(err)
      end
    end
  },

  cassandra = {
    up = [[]],
    teardown = function (connector)
      if not cassandra_has_workspace_enitites(nil, connector)[1] then
        return nil
      end

      local coordinator = connector:connect_migrations()

      -- find out all admin related consumers
      local cql = render([[
        SELECT id FROM $(KEYSPACE).consumers
        WHERE type = 2 ALLOW FILTERING $(PARTITION);
      ]], {
        KEYSPACE = connector.keyspace,
        PARTITION = cassandra_table_is_partitioned(connector, "consumers")
                      and [[ AND partition = 'consumers']]
                      or "",
      })

      for rows, err in coordinator:iterate(cql) do

        if err then
          return log.debug(err)
        end

        for _, row in ipairs(rows) do
          local ws_id, err = connector:query(render([[
            SELECT workspace_id FROM $(KEYSPACE).workspace_entities 
            WHERE unique_field_name='id' 
              AND entity_type='consumers' 
              AND unique_field_value='$(ID)'
              ALLOW FILTERING $(PARTITION);
          ]], {
            KEYSPACE = connector.keyspace,
            ID = row.id,
            PARTITION = cassandra_table_is_partitioned(connector, "workspace_entities")
                      and [[ AND partition = 'workspace_entities']]
                      or "",
          }))

          if not ws_id[1] then
            return log.debug("workspace_id not found for consumer_id=" .. row.id)
          end

          if err then
            return log.debug(err)
          end

          local _, err = connector:query(render([[
            -- revert consumer ws_id from workspace_entities table
            UPDATE $(KEYSPACE).consumers
            SET ws_id=$(WS_ID)
            WHERE id=$(ID) $(PARTITION); 
          ]], {
            KEYSPACE = connector.keyspace,
            WS_ID = ws_id[1].workspace_id,
            ID = row.id,
            PARTITION = cassandra_table_is_partitioned(connector, "consumers")
                      and [[ AND partition = 'consumers']]
                      or "",
          }))

          if err then
            return log.debug(err)
          end
        end

      end

    end
  }
}
