local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"
local stringy = require "stringy"

local function check_custom_id_and_username(value, consumer_t)
  if (consumer_t.custom_id == nil or stringy.strip(consumer_t.custom_id) == "")
    and (consumer_t.username == nil or stringy.strip(consumer_t.username) == "") then
      return false, "At least a \"custom_id\" or a \"username\" must be specified"
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

return Consumers
