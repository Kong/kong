-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local enums = require "kong.enterprise_edition.dao.enums"
local hooks = require "kong.hooks"


local format  = string.format
local ipairs = ipairs


local _M = {}

local UNCOUNTED = {
  -- oauth2 tokens are transient and may be created at high rate/volume
  oauth2_tokens = true,
}

local function countable_schemas(daos)
  local schemas = {}
  for _, dao in pairs(daos or kong.db.daos) do
    local schema = dao.schema
    local name = schema.table_name

    if schema.workspaceable and not UNCOUNTED[name] then
      table.insert(schemas, name)
    end
  end
  return ipairs(schemas)
end


-- Entity count management


--- Retrieve entity counts
--
-- On success, returns a map-like table of entity type names and their respective
-- counts.
--
-- On failure, returns `nil` and an error string
--
-- @tparam[opt] string workspace_id restrict results to a single workspace
-- @treturn table|nil  counts
-- @treturn nil|string error
function _M.entity_counts(workspace_id)
  local counts = {}

  for row, err in kong.db.workspace_entity_counters:each() do
    if err then
      return nil, err
    end

    local entity = row.entity_type

    if (not workspace_id) or workspace_id == row.workspace_id then
      counts[entity] = (counts[entity] or 0) + row.count
    end
  end

  return counts
end


-- Return if entity is relevant to entity counts per workspace. Only
-- non-proxy consumers should not be counted.
local function should_be_counted(entity_type, entity)
  if UNCOUNTED[entity_type] then
    return false
  end

  if entity_type ~= "consumers" then
    return true
  end

  -- some call sites do not provide the consumer.type and only pass
  -- the id of the entity. In that case, we have to first fetch the
  -- complete entity object
  if not entity.type then
    local err

    entity, err = kong.db.consumers:select({id = entity.id})
    if err then
      return nil, err
    end
    if not entity then
      -- The entity is not in the DB. We might be in the middle of the
      -- callback.
      return false
    end
  end

  if entity.type ~= enums.CONSUMERS.TYPE.PROXY then
    return false
  end

  return true
end


function _M.inc_counter(ws, entity_type, entity, count)
  if not should_be_counted(entity_type, entity) then
    return
  end

  local strategy = kong.db.strategy
  if strategy == "postgres" then
    local incr_counter_query = [[
      INSERT INTO workspace_entity_counters(workspace_id, entity_type, count)
      VALUES('%s', '%s', %d)
      ON CONFLICT(workspace_id, entity_type) DO
      UPDATE SET COUNT = workspace_entity_counters.count + excluded.count]]
    local _, err = kong.db.connector:query(format(incr_counter_query, ws, entity_type, count))
    if err then
      return nil, err
    end

  elseif strategy == "off" then -- luacheck: ignore
    -- XXXCORE what happens here in dbless?
  end
end


local function insert_hook(entity, name, _, ws_id)
  if ws_id then
    _M.inc_counter(ws_id, name, entity, 1)
  end
  return entity
end


local function delete_hook(entity, name, _, ws_id, cascade_entries)
  if ws_id then
    _M.inc_counter(ws_id, name, entity, -1)
  end
  for _, entry in ipairs(cascade_entries) do
    if entry.entity.ws_id then
      _M.inc_counter(entry.entity.ws_id, entry.dao.schema.name, entry.entity, -1)
    end
  end
  return entity
end


local function upsert_hook(entity, name, _, ws_id, is_create)
  if is_create and ws_id then
    _M.inc_counter(ws_id, name, entity, 1)
  end
  return entity
end


function _M.register_dao_hooks()
  hooks.register_hook("dao:insert:post", insert_hook)
  hooks.register_hook("dao:delete:post", delete_hook)
  hooks.register_hook("dao:delete_by:post", delete_hook)
  hooks.register_hook("dao:upsert:post", upsert_hook)
  hooks.register_hook("dao:upsert_by:post", upsert_hook)
end

-- reset counters
local function render(template, keys)
  return (template:gsub("$%(([A-Z_]+)%)", keys))
end


local function postgres_run_query_in_transaction(connector, query)
  assert(connector:query(table.concat({ "BEGIN", query, "COMMIT"}, ";")))
end


local function pg_build_queries()
  local truncate_query = [[ TRUNCATE workspace_entity_counters; ]]
  local insert_query = [[
   INSERT INTO workspace_entity_counters
      SELECT ws_id, '$(TABLE)', count(*)
        FROM $(TABLE)
        GROUP BY ws_id;]]

  local code = {}
  table.insert(code, truncate_query)

  for _, name in countable_schemas() do
    local insert
    if name == "consumers" then
      -- Skip counting non-proxy consumers
      insert = render([[
        INSERT INTO workspace_entity_counters
          SELECT ws_id, '$(TABLE)', count(*)
          FROM $(TABLE)
          WHERE type = $(TYPE_PROXY)
          GROUP BY ws_id;]], { TABLE = name, TYPE_PROXY = enums.CONSUMERS.TYPE.PROXY })
    else
      insert = render(insert_query, {TABLE = name})
    end

    table.insert(code, insert)
  end

  return code
end

local function pg_initialize_counters_migration(connector)
  postgres_run_query_in_transaction(connector, table.concat(pg_build_queries(), ";"))
end

function _M.initialize_counters(db)
  local connector = db.connector
  if db.strategy == "postgres" then
    pg_initialize_counters_migration(connector)
  end
end

return _M
