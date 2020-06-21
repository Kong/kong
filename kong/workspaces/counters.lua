local cassandra = require "cassandra"
local enums = require "kong.enterprise_edition.dao.enums"
local hooks = require "kong.hooks"


local format  = string.format
local ipairs = ipairs


local _M = {}


-- Entity count management

function _M.counts(workspace_id)

  local counts = {}
  for v in kong.db.workspace_entity_counters:each() do
    if v.workspace_id ==  workspace_id then
      counts[#counts+1]= v
    end
  end

  local res = {}
  for _, v in ipairs(counts) do
    res[v.entity_type] = v.count
  end

  return res
end


-- Return if entity is relevant to entity counts per workspace. Only
-- non-proxy consumers should not be counted.
local function should_be_counted(entity_type, entity)
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
  if strategy == "cassandra" then
    local _, err = kong.db.connector.cluster:execute([[
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

  elseif strategy == "postgres" then
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


local function delete_hook(entity, name, _, ws_id)
  if ws_id then
    _M.inc_counter(ws_id, name, entity, -1)
  end
  return entity
end


local function upsert_hook(entity, name, _, ws_id, is_create)
  if is_create and ws_id then
    _M.inc_counter(ws_id, name, entity, -1)
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


return _M
