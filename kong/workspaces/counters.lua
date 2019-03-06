local cassandra = require "cassandra"
local dao_wrappers = require "kong.workspaces.dao_wrappers"
local enums = require "kong.enterprise_edition.dao.enums"


local format  = string.format
local ipairs = ipairs
local compat_find_all = dao_wrappers.compat_find_all


local _M = {}


-- Entity count management

function _M.counts(workspace_id)
  local counts, err = compat_find_all("workspace_entity_counters", {
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


return _M
