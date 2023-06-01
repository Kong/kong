-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Helper module for 1500_to_2100 Enterprise migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.
local ce_operations = require "kong.db.migrations.operations.200_to_210"
local log           = require "kong.cmd.utils.log"



local concat = table.concat
local fmt = string.format


local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


local function postgres_run_query_in_transaction(connector, query)
  assert(connector:query(concat({ "BEGIN", query, "COMMIT"}, ";")))
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

local function postgres_remove_prefixes_code(entity, code)
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
end

local function postgres_workspaceable_code(entity, code)
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
      log.debug("ws_fixup_workspaceable_rows: "..  entity.name)

      local code = {}

      -- populate ws_id:
      -- XXX EE shared entities will pick one of the workspaces
      -- they're in.
      local existing_tables, err = postgres_list_tables(connector)
      if err then
        ngx.log(ngx.ERR, [[err: ]], type(err)=='string' and err or type(err))
        return nil, err
      end

      if existing_tables.workspace_entities then
        postgres_workspaceable_code(entity, code)
      end

      postgres_remove_prefixes_code(entity, code)

      postgres_run_query_in_transaction(connector, table.concat(code))
      log.debug("ws_fixup_workspaceable_rows: "..  entity.name .. " DONE")
    end,

    -- Used to assign the ws_id for plugins that depend on a consumer. Those
    -- plugin entities end up with a DB constraint that requires the consumer
    -- and any plugin entity data to exist in the same workspace. But in the
    -- case of a shared consumer it is possible that the ws_id picked for that
    -- consumer does not match the ws_id for the associated plugin entity from
    -- the data in the workspace_entities table.
    --
    -- To avoid hitting this constraint we set the ws_id for each plugin entity
    -- based on the associated consumer, instead of from the workspace_entities
    -- table.
    --
    -- This function does not affect data on the `plugins` table but on tables
    -- created by each installed Kong Plugin.
    ws_fixup_consumer_plugin_rows = function(_, connector, entity)
      log.debug("ws_fixup_consumer_plugin_rows: "..  entity.name)

      local code = {}

      -- customers can be in the middle of a failed 1.5 -> 2.1 migration with no
      -- way to create the ws_migrations_backup table. In this case, proceed
      -- with the migration to fix the customer.
      local existing_tables, err = postgres_list_tables(connector)
      if err then
        ngx.log(ngx.ERR, [[err: ]], type(err)=='string' and err or type(err))
        return nil, err
      end

      if existing_tables.ws_migrations_backup then
        for _, unique in ipairs(entity.uniques) do
          table.insert(code,
            render([[
              INSERT INTO ws_migrations_backup (entity_type, entity_id, unique_field_name, unique_field_value)
              SELECT '$(TABLE)', $(TABLE).$(PK)::text, '$(UNIQUE)', $(TABLE).$(UNIQUE)
              FROM $(TABLE);
            ]], {
              TABLE = entity.name,
              PK = entity.primary_key,
              UNIQUE = unique
            })
          )
        end
      end

      local consumer_plugin = false
      for _, fk in ipairs(entity.fks) do
        if fk.reference == "consumers" then
          consumer_plugin = true
          break
        end
      end
      if consumer_plugin then
        table.insert(code,
          render([[
            UPDATE $(TABLE)
            SET ws_id = c.ws_id
            FROM consumers c
            WHERE $(TABLE).consumer_id = c.id;
          ]], {
            TABLE = entity.name
          })
        )
      else
        -- If this is not a consumer based plugin, fall back to existing
        -- behavior for setting ws_id from workspace_entities table.
        if existing_tables.workspace_entities then
          postgres_workspaceable_code(entity, code)
        end
      end

      postgres_remove_prefixes_code(entity, code)

      postgres_run_query_in_transaction(connector, table.concat(code))
      log.debug("ws_fixup_consumer_plugin_rows: "..  entity.name .. " DONE")
    end,

    ws_clean_kong_admin_rbac_user = function(_, connector)
      connector:query([[
        UPDATE rbac_users
           SET name = 'kong_admin'
         WHERE name = 'default:kong_admin';
      ]])
    end,

    ws_set_default_ws_for_admin_entities = function(_, connector)
      local code = {}
      local entities = { "rbac_user" }

      for _, e in ipairs(entities) do
        table.insert(code,
          render([[

            -- assign admin linked $(TABLE)' ws_id to default ws id

            update $(TABLE)
            set ws_id = (select id from workspaces where name='default')
            where id in (select $(COLUMN) from admins);
          ]], {
            TABLE = e .. "s",
            COLUMN = e .. "_id",
          })
        )
      end

      postgres_run_query_in_transaction(connector, table.concat(code))
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

    has_workspace_entities = function(_, connector)
      return connector:query([[
        SELECT * FROM pg_catalog.pg_tables WHERE tablename='workspace_entities';
      ]])
    end,

  },

}


--------------------------------------------------------------------------------
-- Higher-level operations for Workspace data migration
--------------------------------------------------------------------------------


local function ws_adjust_data(ops, connector, entities)
  for _, entity in ipairs(entities) do
    log.debug("adjusting data for: " .. entity.name)
    ops.ws_fixup_workspaceable_rows(ops, connector, entity)
    log.debug("adjusting data for: " .. entity.name .. " ...DONE")
  end
end


postgres.teardown.ws_adjust_data = ws_adjust_data


local function ws_migrate_plugin(plugin_entities)

  local function ws_migration_teardown(ops)
    return function(connector)
      for _, entity in ipairs(plugin_entities) do
        ops.ws_fixup_consumer_plugin_rows(ops, connector, entity)
      end
    end
  end

  return {
    postgres = {
      up = "",
      teardown = ws_migration_teardown(postgres.teardown),
    },
  }
end


--------------------------------------------------------------------------------


local ee_operations = {
  postgres = postgres,
  ws_migrate_plugin = ws_migrate_plugin,
  utils = {
    render = render,
    postgres_has_workspace_entities = postgres.teardown.has_workspace_entities,
  },
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
