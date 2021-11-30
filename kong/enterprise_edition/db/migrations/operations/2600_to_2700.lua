-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Helper module for 2600_to_2700 Enterprise migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.
local cassandra   = require "cassandra"
local constants   = require "kong.constants"
local log         = require "kong.cmd.utils.log"
local operations  = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"


local cassandra_table_is_partitioned = operations.utils.cassandra_table_is_partitioned
local render = operations.utils.render

local ADMIN_CONSUMER_USERNAME_SUFFIX = constants.ADMIN_CONSUMER_USERNAME_SUFFIX

local function string_ends(str, suffix)
  return str:sub(-#(suffix)) == suffix
end

local function cassandra_migrate_license_data(connector)
  local coordinator = connector:connect_migrations()
  local cluster = connector.cluster;

  -- keep a copy of all current license_data
  for rows, err in coordinator:iterate("SELECT * FROM license_data") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      assert(cluster:execute("UPDATE license_data_tmp SET req_cnt = req_cnt + ? WHERE license_creation_date = ? and node_id = ?",
        {
          cassandra.counter(row.req_cnt),
          cassandra.timestamp(row.license_creation_date),
          cassandra.uuid(row.node_id)
        }))
    end
  end

  -- drop table
  assert(connector:query([[
    DROP TABLE IF EXISTS license_data;
  ]]))

  connector:wait_for_schema_consensus()

  -- recreate table with the new field and types
  assert(connector:query([[
    /* License data */
    CREATE TABLE IF NOT EXISTS license_data (
      node_id                 uuid,
      license_creation_date   timestamp,
      year                    int,
      month                   int,
      req_cnt                 counter,
      PRIMARY KEY (node_id, license_creation_date, year, month));
  ]]))

  connector:wait_for_schema_consensus()

  -- copy data from temp table to a new one
  for rows, err in coordinator:iterate("SELECT * FROM license_data_tmp") do
    if err then
      return nil, err
    end

    -- add created_at for old entries (use epoch)
    for _, row in ipairs(rows) do
      assert(cluster:execute(
        "UPDATE license_data SET req_cnt = req_cnt + ? WHERE node_id=? AND license_creation_date=? AND year=? AND month=?",
        {
          cassandra.counter(row.req_cnt),
          cassandra.uuid(row.node_id),
          cassandra.timestamp(row.license_creation_date),
          cassandra.int(0),
          cassandra.int(0)
        }))
    end

  end

  -- drop temp table
   assert(connector:query([[
    DROP TABLE IF EXISTS license_data_tmp;
  ]]))

end

local function cassandra_migrate_consumers(connector)
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


local ee_operations = {
  cassandra_migrate_consumers     = cassandra_migrate_consumers,
  cassandra_migrate_license_data  = cassandra_migrate_license_data,
}

return ee_operations
