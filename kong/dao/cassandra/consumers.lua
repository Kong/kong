local BaseDao = require "kong.dao.cassandra.base_dao"
local consumers_schema = require "kong.dao.schemas.consumers"

local Consumers = BaseDao:extend()

function Consumers:new(properties)
  self._entity = "Consumer"
  self._schema = consumers_schema
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
    },
    drop = "TRUNCATE consumers;"
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
  local plugins_dao = self._factory.plugins_configurations
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

return { consumers = Consumers }
