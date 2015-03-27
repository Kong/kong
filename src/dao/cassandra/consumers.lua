local BaseDao = require "kong.dao.cassandra.base_dao"
local constants = require "kong.constants"

local SCHEMA = {
  id = { type = constants.DATABASE_TYPES.ID },
  custom_id = { type = "string", unique = true, queryable = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local Consumers = BaseDao:extend()

function Consumers:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "custom_id", "created_at" },
      query = [[ INSERT INTO consumers(id, custom_id, created_at) VALUES(?, ?, ?); ]]
    },
    update = {
      params = { "custom_id", "created_at", "id" },
      query = [[ UPDATE consumers SET custom_id = ?, created_at = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM consumers %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM consumers WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM consumers WHERE id = ?; ]]
    },
    __unique = {
      custom_id ={
        params = { "custom_id" },
        query = [[ SELECT id FROM consumers WHERE custom_id = ?; ]]
      }
    }
  }

  Consumers.super.new(self, properties)
end

return Consumers
