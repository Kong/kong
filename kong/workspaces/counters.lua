local cassandra = require "cassandra"
local enums = require "kong.enterprise_edition.dao.enums"
local singletons = require "kong.singletons"


local format  = string.format
local ipairs = ipairs


local _M = {}


-- Entity count management

function _M.counts(workspace_id)
  local counts, err = singletons.db.workspace_entity_counters:select_all({
    workspace_id = workspace_id
  })
  if err then
    return nil, err
  end

  local res = {}
  for _, v in ipairs(counts) do
    res[v.entity_type] = v.count
  end

  return res
end


-- Return if entity is relevant to entity counts per workspace. Only
-- non-proxy consumers should not be counted.
local function should_be_counted(dao, entity_type, entity)
  if entity_type ~= "consumers" then
    return true
  end

  -- some call sites do not provide the consumer.type and only pass
  -- the id of the entity. In that case, we have to first fetch the
  -- complete entity object
  if not entity.type then
    local err

    local consumers = dao.consumers
    entity, err = consumers:select({id = entity.id})
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


function _M.inc_counter(dao, ws, entity_type, entity, count)

  if not should_be_counted(dao, entity_type, entity) then
    return
  end

  if dao.strategy == "cassandra" then
    local _, err = dao.connector.cluster:execute([[
      UPDATE workspace_entity_counters set
      count=count + ? where workspace_id = ? and entity_type= ?]],
      {cassandra.counter(count), cassandra.uuid(ws), entity_type},
      {
        counter = true,
        prepared = true,
    })
    if err then
      return nil, err
    end

  else
    local incr_counter_query = [[
      INSERT INTO workspace_entity_counters(workspace_id, entity_type, count)
      VALUES('%s', '%s', %d)
      ON CONFLICT(workspace_id, entity_type) DO
      UPDATE SET COUNT = workspace_entity_counters.count + excluded.count]]
    local _, err = dao.connector:query(format(incr_counter_query, ws, entity_type, count))
    if err then
      return nil, err
    end
  end
end


local workspaces = require "kong.workspaces"

local function pg_initialize_counters_migration(dao)
  dao:truncate("workspace_entity_counters")
  local _, err = dao:query([[
                   insert into workspace_entity_counters
                      select workspace_id, entity_type, count(distinct entity_id)
                        from workspace_entities
                        group by workspace_id, entity_type; ]])
  if err then
    return nil, err
  end
end

-- Cassandra strategy for counting all entities per workspace: We
-- iterate all the table once incrementing the counter to the
-- corresponding workspace+entity_type. Only increment for the primary
-- field
local function c_initialize_counters_migration(dao)
  dao:truncate_table("workspace_entity_counters")
  local db = dao
  local workspaceable_relations = workspaces.get_workspaceable_relations()
  local counts = {}

  -- get coordinator if present, else set one.
  -- also, set keyspace
  local coordinator ,err  = db:get_coordinator()
  if err then
    local ok, err = db:first_coordinator()
    if not ok then
      return nil, "could not find coordinator: " .. err
    end
    coordinator ,err  = db:get_coordinator()
    if err then
      error(err)
    end
    if coordinator then
      local keyspace = db.cluster_options.keyspace
      local ok, err = db:coordinator_change_keyspace(keyspace)
      if not ok then
        return nil, err
      end
    end
  end

  -- for every workspace_entity primary_key row increment a counter
  -- for its workspace+entity_type
  for rows, err, page in coordinator:iterate("SELECT * FROM workspace_entities",
    nil,
    {page_size = 1000}) do
    for _, row in ipairs(rows) do
      if workspaceable_relations[row.entity_type].primary_key == row.unique_field_name then
        counts[row.workspace_id] = counts[row.workspace_id] or {}
        counts[row.workspace_id][row.entity_type] = (counts[row.workspace_id][row.entity_type] or 0) + 1
      end
    end
  end

  -- fill the blanks with 0s
  for ws_id, ws in pairs(counts) do
    for entity_type, relation_info in pairs(workspaceable_relations) do
      counts[ws_id][entity_type] = counts[ws_id][entity_type] or 0
    end
  end

  return counts
end

function _M.initialize_counters(dao)
  if dao.db_type == "postgres" then
    pg_initialize_counters_migration(dao)
  elseif dao.db_type == "cassandra" then
    local workspaces_counts = c_initialize_counters_migration(dao)

    for k, v in pairs(workspaces_counts) do
      for entity_type, count in pairs(v) do
        _M.inc_counter(dao, k, entity_type,
          {type = enums.CONSUMERS.TYPE.PROXY}, count)
      end
    end

  end

end


return _M
