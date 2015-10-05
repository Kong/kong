local plugins_schema = require "kong.dao.schemas.plugins"
local query_builder = require "kong.dao.cassandra.query_builder"
local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"
local cjson = require "cjson"

local Plugins = BaseDao:extend()

function Plugins:new(properties)
  self._table = "plugins"
  self._schema = plugins_schema

  Plugins.super.new(self, properties)
end

-- @override
function Plugins:_marshall(t)
  if type(t.config) == "table" then
    t.config = cjson.encode(t.config)
  end

  return t
end

-- @override
function Plugins:_unmarshall(t)
  -- deserialize configs (tables) string to json
  if type(t.config) == "string" then
    t.config = cjson.decode(t.config)
  end
  -- remove consumer_id if null uuid
  if t.consumer_id == constants.DATABASE_NULL_ID then
    t.consumer_id = nil
  end

  return t
end

-- @override
function Plugins:update(t)
  if not t.consumer_id then
    t.consumer_id = constants.DATABASE_NULL_ID
  end
  return Plugins.super.update(self, t)
end

function Plugins:find_distinct()
  -- Open session
  local session, err = Plugins.super._open_session(self)
  if err then
    return nil, err
  end

  local select_q = query_builder.select(self._table)

  -- Execute query
  local distinct_names = {}
  for rows, err in Plugins.super.execute(self, select_q, nil, nil, {auto_paging=true}) do
    if err then
      return nil, err
    end
    for _, v in ipairs(rows) do
      -- Rows also contains other properties, so making sure it's a plugin
      if v.name then
        distinct_names[v.name] = true
      end
    end
  end

  -- Close session
  local socket_err = Plugins.super._close_session(self, session)
  if socket_err then
    return nil, socket_err
  end

  local result = {}
  for k, _ in pairs(distinct_names) do
    table.insert(result, k)
  end

  return result, nil
end

return {plugins = Plugins}
