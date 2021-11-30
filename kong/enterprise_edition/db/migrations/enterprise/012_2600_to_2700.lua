-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"
local log        = require "kong.cmd.utils.log"
local constants  = require "kong.constants"

local cassandra_table_is_partitioned = operations.utils.cassandra_table_is_partitioned
local render = operations.utils.render

local ADMIN_CONSUMER_USERNAME_SUFFIX = constants.ADMIN_CONSUMER_USERNAME_SUFFIX

local function string_ends(str, suffix)
  return str:sub(-#(suffix)) == suffix
end

return {
  postgres = {
    up = [[
      UPDATE consumers 
      SET
        username = CONCAT(username, '_ADMIN_'),
        username_lower = CONCAT(username_lower, '_admin_')
      WHERE
        username !~ '_ADMIN_$'
      AND
        type = 2;
    ]], 
  },

  cassandra = {
    up = [[
    ]],
    teardown = function (connector)
      local coordinator = connector:connect_migrations()

      -- find out all admin related consumers
      local cql = render([[
        SELECT id, username, username_lower FROM $(KEYSPACE).consumers
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

          if row.username and not string_ends(row.username, ADMIN_CONSUMER_USERNAME_SUFFIX) then
            local _, err = connector:query(render([[
              UPDATE $(KEYSPACE).consumers
              SET	username='$(USERNAME)', username_lower='$(USERNAME_LOWER)'
              WHERE id=$(ID) $(PARTITION);
            ]], {
              KEYSPACE = connector.keyspace,
              ID = row.id,
              USERNAME = row.username .. ADMIN_CONSUMER_USERNAME_SUFFIX,
              USERNAME_LOWER = (row.username_lower or "") .. ADMIN_CONSUMER_USERNAME_SUFFIX:lower(),
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

    end
  }
}
