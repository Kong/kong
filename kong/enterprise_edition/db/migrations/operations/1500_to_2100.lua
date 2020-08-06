-- Helper module for 1500_to_2100 Enterprise migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.
local ce_operations = require "kong.db.migrations.operations.200_to_210"


local concat = table.concat
local fmt = string.format


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


local function postgres_run_query_in_transaction(connector, query)
  connector:query(concat({ "BEGIN", query, "COMMIT"}, ";"))
end


local function postgres_list_tables(connector)
  local tables = {}

  local sql = fmt([[
    SELECT table_name
      FROM information_schema.tables
     WHERE table_schema='%s'
  ]], connector.config.schema)
  local rows, err = connector:query(sql)
  if err then
    return nil, err
  end

  for _, v in ipairs(rows) do
    local _, vv = next(v)
    tables[vv] = true
  end

  return tables
end


local function cassandra_list_tables(connector)
  local coordinator = connector:connect_migrations()
  local tables = {}

  local cql = fmt([[
    SELECT table_name
      FROM system_schema.tables
     WHERE keyspace_name='%s';
  ]], connector.keyspace)
  for rows, err in coordinator:iterate(cql) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      tables[row.table_name] = true
    end
  end

  return tables
end


local function cassandra_foreach_row(connector, table_name, f)
  local coordinator = connector:connect_migrations()

  for rows, err in coordinator:iterate("SELECT * FROM " .. table_name) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      f(row)
    end
  end
end


local memo_prefix_fixups
local function cassandra_get_prefix_fixups_table(connector)
  -- memoize results
  if memo_prefix_fixups then
    return memo_prefix_fixups
  end

  memo_prefix_fixups = {}
  cassandra_foreach_row(connector, "workspaces", function(e)
    memo_prefix_fixups[e.name .. ":"] = e.id .. ":"
  end)

  return memo_prefix_fixups
end


local memo_is_partitioned = {}
local function cassandra_table_is_partitioned(connector, table_name)
  -- memoize results
  if memo_is_partitioned[table_name] ~= nil then
    return memo_is_partitioned[table_name]
  end

  -- Assume a release version number of 3 & greater will use the same schema.
  local cql
  if connector.major_version >= 3 then
    cql = [[
      SELECT * FROM system_schema.columns
      WHERE keyspace_name = '$(KEYSPACE)'
      AND table_name = '$(TABLE)'
      AND column_name = 'partition';
    ]]
  else
    cql = [[
      SELECT * FROM system.schema_columns
      WHERE keyspace_name = '$(KEYSPACE)'
      AND columnfamily_name = '$(TABLE)'
      AND column_name = 'partition';
    ]]
  end

  cql = render(cql, {
    KEYSPACE = connector.keyspace,
    TABLE = table_name,
  })

  local rows, err = connector:query(cql, {}, nil, "read")
  if err then
    return nil, err
  end

  -- Assume a release version number of 3 & greater will use the same schema.
  if connector.major_version >= 3 then
    return rows[1] and rows[1].kind == "partition_key"
  end

  memo_is_partitioned[table_name] = not not rows[1]
  return memo_is_partitioned[table_name]
end


--------------------------------------------------------------------------------
-- Postgres operations for Workspace data migration
--------------------------------------------------------------------------------


local postgres = {

  up = {
  },

  teardown = {

    ----------------------------------------------------------------------------
    -- Set `ws_id` fields based on values from `workspace_entities`,
    -- and remove prefixes from unique values.
    ws_fixup_workspaceable_rows = function(_, connector, entity)
      local code = {}

      -- insert ws_id:

      -- XXX EE test what happens here with shared entities
      -- XXX EE for admin-consumers, can we just put them in default?
      local tables, err = postgres_list_tables(connector)
      if err then
        ngx.log(ngx.ERR, kong.log.inspect(err))
        return nil, err
      end

      if tables.workspace_entities then
        table.insert(code,
          render([[

            -- fixing up workspaceable rows for $(TABLE)

            UPDATE $(TABLE)
            SET ws_id = we.workspace_id
            FROM workspace_entities we
            WHERE entity_type='$(TABLE)'
              AND unique_field_name='$(PK)'
              AND unique_field_value=$(TABLE).$(PK)::text;
          ]], {
            TABLE = entity.name,
            PK = entity.primary_key,
          })
        )
      end

      -- remove prefixes:

      if #entity.uniques > 0 then
        local fields = {}
        for _, f in ipairs(entity.uniques) do
          table.insert(fields, f .. " = regexp_replace(" .. f .. ", '^(' || (SELECT string_agg(name, '|') FROM workspaces) ||'):', '')")
        end

        table.insert(code,
          render([[
            UPDATE $(TABLE) SET $(FIELDS);
          ]], {
            TABLE = entity.name,
            FIELDS = table.concat(fields, ", "),
          })
        )
      end

      postgres_run_query_in_transaction(connector, table.concat(code))
    end,

    ws_clean_kong_admin_rbac_user = function(_, connector)
      connector:query([[
        UPDATE rbac_users
           SET name = 'kong_admin'
         WHERE name = 'default:kong_admin';
      ]])
    end,

    drop_run_on = function(_, connector)
      connector:query([[
        DO $$
        BEGIN
          ALTER TABLE IF EXISTS ONLY "plugins" DROP COLUMN "run_on";
        EXCEPTION WHEN UNDEFINED_COLUMN THEN
          -- Do nothing, accept existing state
        END;
        $$;
      ]])
    end,

  },

}


--------------------------------------------------------------------------------
-- Cassandra operations for Workspace data migration
--------------------------------------------------------------------------------


local cassandra = {

  up = {
  },

  teardown = {

    ----------------------------------------------------------------------------
    -- Set `ws_id` fields based on values from `workspace_entities`.
    ws_fixup_workspaceable_rows = function(_, connector, entity)
      local code = {}

      local ws_prefix_fixups = cassandra_get_prefix_fixups_table(connector)
      local tables = cassandra_list_tables(connector)

      cassandra_foreach_row(connector, entity.name, function(row)
        local ws_name
        local fields = {}

        for _, f in ipairs(entity.uniques) do
          local value = row[f]
          if row[f] then
            local colon_pos = row[f]:find(":")
            if colon_pos then
              ws_name = ws_name or row[f]:sub(1, colon_pos)
              value = string.gsub(row[f], "^[^:]+:", ws_prefix_fixups)
            end

            table.insert(fields, fmt("%s = '%s'", f, value))
          end
        end

        if not ws_name and tables.workspace_entities then
          -- assumes that primary keys are 'id',
          -- which is currently true for all workspaceable entities
          ws_name = ws_name or connector:query(render([[
            SELECT workspace_name FROM $(KEYSPACE).workspace_entities
            WHERE entity_id = '$(ID)' LIMIT 1 ALLOW FILTERING;
          ]], {
            KEYSPACE = connector.keyspace,
            ID = row[entity.primary_key],
           }))

          ws_name = ws_name                and
                    ws_name[1]             and
                    ws_name[1].workspace_name and
                    ws_name[1].workspace_name .. ":"
        end
        if not ws_name or not ws_prefix_fixups[ws_name] then
          -- data is already adjusted, bail out
          return
        end

        table.insert(fields, "ws_id = " .. ws_prefix_fixups[ws_name]:sub(1, -2))

        table.insert(code, render([[
          UPDATE $(KEYSPACE).$(TABLE) SET $(FIELDS) WHERE id = $(ID) $(PARTITION);
        ]], {
          KEYSPACE = connector.keyspace,
          TABLE = entity.name,
          FIELDS = table.concat(fields, ", "),
          ID = row[entity.primary_key],
          PARTITION = cassandra_table_is_partitioned(connector, entity.name)
                      and fmt([[ AND partition = '%s']], entity.name)
                      or "",
        }))
      end)

      connector:query(table.concat(code, ";\n"))
    end,

    ws_clean_kong_admin_rbac_user = function(_, connector)
      local coordinator = connector:connect_migrations()

      local cql = render([[
        SELECT *
          FROM $(KEYSPACE).workspace_entities
         WHERE unique_field_value = 'kong_admin'
      ]], {
        KEYSPACE = connector.keyspace,
      })

      for rows, err in coordinator:iterate(cql) do
        if err then
          return nil, err
        end

        for _, row in ipairs(rows) do
          if row.entity_type == "rbac_users" then
            connector:query(render([[
              UPDATE $(KEYSPACE).rbac_users
                 SET name = 'kong_admin'
               WHERE id = $(ID);
            ]], {
              KEYSPACE = connector.keyspace,
              ID = row.entity_id,
            }))
          end
        end
      end
    end,

    drop_run_on = function(_, connector)
      -- no need to drop the actual row from the database
      -- (this operation is not reentrant in Cassandra)
      --[===[
      assert(connector:query([[
        ALTER TABLE plugins DROP run_on;
      ]]))
      ]===]
    end,

  },

}


--------------------------------------------------------------------------------
-- Higher-level operations for Workspace data migration
--------------------------------------------------------------------------------


local function ws_adjust_data(ops, connector, entities)
  for _, entity in ipairs(entities) do
    ops.ws_fixup_workspaceable_rows(ops, connector, entity)
  end
end


postgres.teardown.ws_adjust_data = ws_adjust_data
cassandra.teardown.ws_adjust_data = ws_adjust_data


--------------------------------------------------------------------------------


local ee_operations = {
  postgres = postgres,
  cassandra = cassandra,
}


-- merge ce_operations into ee_operations table
for db, stages in pairs(ce_operations) do
  if type(stages) == "table" then
    for stage, ops in pairs(stages) do
      for name, fn in pairs(ops) do
        if not ee_operations[db][stage][name] then
          ee_operations[db][stage][name] = fn
        end
      end
    end
  end
end


return ee_operations
