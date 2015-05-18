local BaseDao = require "kong.dao.cassandra.base_dao"
local stringy = require "stringy"
local constants = require "kong.constants"
local PluginsConfigurations = require "kong.dao.cassandra.plugins_configurations"

local function check_custom_id_and_username(value, consumer_t)
  if (consumer_t.custom_id == nil or stringy.strip(consumer_t.custom_id) == "")
    and (consumer_t.username == nil or stringy.strip(consumer_t.username) == "") then
      return false, "At least a 'custom_id' or a 'username' must be specified"
  end
  return true
end

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  custom_id = { type = "string", unique = true, queryable = true, func = check_custom_id_and_username },
  username = { type = "string", unique = true, queryable = true, func = check_custom_id_and_username },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local Consumers = BaseDao:extend()

function Consumers:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      args_keys = { "id", "custom_id", "username", "created_at" },
      query = [[ INSERT INTO consumers(id, custom_id, username, created_at) VALUES(?, ?, ?, ?); ]]
    },
    update = {
      args_keys = { "custom_id", "username", "created_at", "id" },
      query = [[ UPDATE consumers SET custom_id = ?, username = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM consumers %s; ]]
    },
    select_one = {
      args_keys = { "id" },
      query = [[ SELECT * FROM consumers WHERE id = ?; ]]
    },
    delete = {
      args_keys = { "id" },
      query = [[ DELETE FROM consumers WHERE id = ?; ]]
    },
    __unique = {
      custom_id ={
        args_keys = { "custom_id" },
        query = [[ SELECT id FROM consumers WHERE custom_id = ?; ]]
      },
      username ={
        args_keys = { "username" },
        query = [[ SELECT id FROM consumers WHERE username = ?; ]]
      }
    }
  }

  Consumers.super.new(self, properties)
end

-- @override
function Consumers:delete(consumer_id)
  local ok, err = Consumers.super.delete(self, consumer_id)
  if not ok then
    return false, err
  end

  -- delete all related plugins configurations
  local plugins_dao = PluginsConfigurations(self._properties)
  local query, args_keys, errors = plugins_dao:_build_where_query(plugins_dao._queries.select.query, {
    consumer_id = consumer_id
  })
  if errors then
    return nil, errors
  end

  for _, rows, page, err in plugins_dao:_execute_kong_query({query=query, args_keys=args_keys}, {consumer_id=consumer_id}, {auto_paging=true}) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local ok_del_plugin, err = plugins_dao:delete(row.id)
      if not ok_del_plugin then
        return nil, err
      end
    end
  end

  return ok
end

return Consumers
