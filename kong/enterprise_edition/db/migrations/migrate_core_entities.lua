-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces  = require "kong.workspaces"
local counters    = require "kong.workspaces.counters"
local log         = require "kong.cmd.utils.log"

local fmt = string.format
local concat = table.concat

local ngx = ngx
local ngx_null = ngx.null


-- XXXCORE FIXME this information now lives in the schema for fields
local unique_accross_ws = {
  plugins    = true,
  rbac_users = true,
  workspaces = true,
  snis = true,
}

local DEFAULT_WORKSPACE = workspaces.DEFAULT_WORKSPACE
local WORKSPACE_DELIMITER = ":"

-- More than WORKSPACE_THRESHOLD entities, and we do not run this migration
local WORKSPACE_THRESHOLD = 100


-- cache
local workspaceable_relations = nil


local function get_workspaceable_relations()
  if not workspaceable_relations then
    workspaceable_relations = {}
    for name, dao in pairs(kong.db.daos) do
      local schema = dao.schema
      if schema.workspaceable then
        local constraints = {
          unique_keys = {},
          primary_keys = schema.primary_key,
          primary_key = schema.primary_key[1],
        }
        for fname, fdata in schema:each_field() do
          if fdata.unique then
            constraints.unique_keys[fname] = true
          end
        end
        workspaceable_relations[name] = constraints
      end
    end
  end

  return setmetatable({},  {
    __index = workspaceable_relations,
    __newindex = function()
      error "immutable table"
    end,
    __pairs = function()
      return next, workspaceable_relations, nil
    end,
    __metatable = false,
  })
end


local strategies = function(connector)

  local function pg_escape_literal(literal)
    if literal == nil or
       literal == ngx_null then
      return "NULL"
    end
    return connector:escape_literal(literal)
  end

  local function pg_escape_identifier(identifier)
    return connector:escape_identifier(identifier)
  end

  return {
    postgres = {
      default_workspace = function()
        local res, err = connector:query(fmt([[
          SELECT id, name FROM workspaces WHERE name = %s LIMIT 1;
        ]], pg_escape_literal(DEFAULT_WORKSPACE)))
        if err then return nil, err end
        return res[1]
      end,

      should_run = function()
        local res, err = connector:query([[
          SELECT SUM(count) as count FROM workspace_entity_counters;
        ]])
        if err then return false, err end
        local count = 0
        if res[1].count and res[1].count ~= ngx_null then
          count = res[1].count
        end
        return count < WORKSPACE_THRESHOLD
      end,

      workspace_entity_ids = function()
        local res, err = connector:query([[
          SELECT entity_id, unique_field_name FROM workspace_entities;
        ]])
        if err then return nil, err end
        if not res then return {} end
        local ids = {}
        for i = 1, #res do
          if not ids[res[i].entity_id] then
            ids[res[i].entity_id] = {}
          end
          ids[res[i].entity_id][res[i].unique_field_name] = true
        end
        return ids
      end,

      entities = function(entity)
        return connector:iterate(fmt([[
          SELECT * FROM %s;
        ]], pg_escape_identifier(entity)))
      end,

      add_entity = function(workspace, entity)
        return fmt([[
          INSERT INTO workspace_entities (workspace_name, workspace_id, entity_id, entity_type, unique_field_name, unique_field_value)
          VALUES (%s, %s, %s, %s, %s, %s);
          ]],
          pg_escape_literal(workspace.name),
          pg_escape_literal(workspace.id),
          pg_escape_literal(entity.id),
          pg_escape_literal(entity.entity_type),
          pg_escape_literal(entity.unique_field_name),
          pg_escape_literal(entity.unique_field_value)
        )
      end,

      update_entity_unique_field = function(entity)
        return fmt([[
          UPDATE %s SET %s = %s WHERE %s NOT LIKE %s AND id = %s;
          ]],
          pg_escape_identifier(entity.entity_type),
          pg_escape_identifier(entity.unique_field_name),
          pg_escape_literal(DEFAULT_WORKSPACE .. WORKSPACE_DELIMITER .. entity.unique_field_value),
          pg_escape_identifier(entity.unique_field_name),
          pg_escape_literal('%' .. WORKSPACE_DELIMITER .. '%'),
          pg_escape_literal(entity.id)
        )
      end,

      update_entity_field = function(entity, entity_schema, field_name, field_value)
        return fmt([[
          UPDATE %s SET %s = %s WHERE id = %s;
          ]],
          pg_escape_identifier(entity_schema.name),
          pg_escape_identifier(field_name),
          field_value,
          pg_escape_literal(entity.id)
        )
      end,

      update_cache_key = function(entity_type, entity_id, cache_key)
        return fmt([[ UPDATE %s SET cache_key = %s WHERE id = %s; ]],
                   pg_escape_identifier(entity_type),
                   pg_escape_literal(cache_key),
                   pg_escape_literal(entity_id))
      end,
    },
  }
end


-- updates entity data with "delta" or missing information during the migration between CE and EE
local function entity_correction(queries, entity_fixes, entity_schema, entity)
  -- consumers
  if entity_schema.name == "consumers" then
    -- update default value for field 'type' mainly for cassandra
    if not entity.type then
      entity_fixes[#entity_fixes + 1] = queries.update_entity_field(entity, entity_schema, "type", 0)
    end
  end
end


local function migrate_core_entities(db, opts)
  local connector = db.connector
  local strategy = db.strategy
  local conf = opts.conf

  db.plugins:load_plugin_schemas(conf.loaded_plugins)
  local entities = get_workspaceable_relations()

  local queries = strategies(connector)[strategy]

  if not queries.should_run() and not opts.force then
    return nil, fmt("There are more than %d EE entities on the database, run " ..
                    "with the --force flag to force running this migration",
                    WORKSPACE_THRESHOLD)
  end

  local default_workspace, err = queries.default_workspace()
  if err then return nil, err end
  if not default_workspace then return nil, "default workspace not found" end


  -- Map containing existing workspace entity ids. It's important we get it
  -- at the start (before any new have been added).
  -- We need this for proper entity counts
  local ws_entity_map = queries.workspace_entity_ids()

  local ws_entity_exists = function(entity_id, field)
    return ws_entity_map[entity_id] and ws_entity_map[entity_id][field]
  end

  local workspace_entities = {}

  -- Anything goes in here, different in scope to workspace_entities
  local entity_fixes = {}

  local entity_log_counters = setmetatable({}, {
    __index = function() return 0 end
  })

  for model, relation in pairs(entities) do
    local schema = db.daos[model].schema
    local composite_cache_key = schema.cache_key and #schema.cache_key > 1

    for row, row_err in queries.entities(model) do
      if not row then
        return nil, "failed to get entity row: " .. row_err
      end
      -- Add workspace_entity for this model
      local update_counter = false
      local entity_id = row[relation.primary_key]
      local unique_field_name = relation.primary_key

      -- add entity correction if needed
      entity_correction(queries, entity_fixes, schema, row)

      -- One entity per primary key
      -- check if primary key relation of entity is already migrated
      if not ws_entity_exists(entity_id, unique_field_name) then
        workspace_entities[#workspace_entities + 1] = {
          id = entity_id,
          entity_type = model,
          unique_field_name = unique_field_name,
          unique_field_value = entity_id,
          pk = true,
        }
        update_counter = true
      end

      -- One entity per each unique key
      for unique_key, _ in pairs(relation.unique_keys) do
        local unique_field_val = row[unique_key]

        -- check if unique keys relation of entity are already migrated
        if not ws_entity_exists(entity_id, unique_key) then
          workspace_entities[#workspace_entities + 1] = {
            id = entity_id,
            entity_type = model,
            unique_field_name = unique_key,
            unique_field_value = unique_field_val,
            pk = false,
          }

          update_counter = true
        end
      end

      if update_counter then
        entity_log_counters[model] = entity_log_counters[model] + 1
        entity_log_counters.__all = entity_log_counters.__all + 1
      end

      -- Quick fixes here. Either something we missed on previous versions of
      -- this migration script or cases not directly related to
      -- workspace_entities. Or both!

      -- Fix for including workspace_id on persisted cache_keys
      if row.cache_key and row.cache_key ~= ngx_null and composite_cache_key then
        -- Check if entity has core or ee cache_key
        -- XXX: Any better idea besides counting separators?
        --
        -- 1. The only other idea I can think of is trying to match _any_
        -- workspace on it (ie: has_workspace or not)
        --
        -- 2. The other possibility is trying to go for less granularity,
        -- and write a query that updates all of them, but that will not
        -- work for cassandra since we need to check string occurrence

        local is_ee_cache_key = select(2, row.cache_key:gsub(':', ''))
                             == select(2, db[model]:cache_key(entity_id):gsub(':', ''))
        if not is_ee_cache_key then
          local new_cache_key = row.cache_key .. ":" .. default_workspace.id
          entity_fixes[#entity_fixes + 1] = queries.update_cache_key(model, entity_id, new_cache_key)
        end
      end
    end
  end

  log("Found %d entities to migrate to the %s workspace", entity_log_counters.__all,
      DEFAULT_WORKSPACE)

  for model, count in pairs(entity_log_counters) do
    log.verbose("%s: %d entities", model, count)
  end

  if #entity_fixes > 0 then
    log("Also applying %d fixes", #entity_fixes)
  end

  local buffer = {}
  if strategy == "postgres" then
    buffer[#buffer + 1] = "BEGIN;"
  end

  for _, entity in ipairs(workspace_entities) do
    -- Add entity
    buffer[#buffer + 1] = queries.add_entity(default_workspace, entity)

    -- Update unique_key values (not pk)
    if not entity.pk and entity.unique_field_value
       and entity.unique_field_value ~= ngx_null
       and not unique_accross_ws[entity.entity_type] then

       -- Explicit DELIMITER in name check (cassandra mostly)
       if not entity.unique_field_value:find(WORKSPACE_DELIMITER) then
         buffer[#buffer + 1] = queries.update_entity_unique_field(entity)
       end
    end
  end

  for _, fix in pairs(entity_fixes) do
    buffer[#buffer + 1] = fix
  end

  if strategy == "postgres" then
    buffer[#buffer + 1] = "COMMIT;"
    assert(connector:query(concat(buffer, '\n')))
  end

  counters.initialize_counters(db)

  if entity_log_counters.__all > 0 then
    log("Migrated %d entities to the %s workspace", entity_log_counters.__all,
        DEFAULT_WORKSPACE)
  end

  if #entity_fixes > 0 then
    log("Applied %d fixes", #entity_fixes)
  end

  return true, nil
end


return migrate_core_entities
