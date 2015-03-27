local constants = require "kong.constants"
local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  username = { type = "string", required = true, queryable = true },
  password = { type = "string", required = true },
  consumer_id = { type = constants.DATABASE_TYPES.ID,
                  required = true,
                  foreign = true,
                  immutable = true },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}

local BasicAuthDAO = BaseDao:extend()

function BasicAuthDAO:new(properties)
  self._entity = "basicauth_credentials"
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "username", "password", "consumer_id", "created_at" },
      query = [[ INSERT INTO basicauth_credentials(username, password, consumer_id, created_at) VALUES(?, ?, ?, ?); ]]
    },
    select = {
      query = [[ SELECT * FROM basicauth_credentials %s; ]]
    },
    select_one = {
      params = { "username" },
      query = [[ SELECT * FROM basicauth_credentials WHERE username = ?; ]]
    },
    update = {
      params = { "password", "username" },
      query = [[ UPDATE basicauth_credentials SET password = ? WHERE username = ?; ]]
    },
    delete = {
      params = { "username" },
      query = [[ DELETE FROM basicauth_credentials WHERE username = ?; ]]
    },
    __foreign = {
      consumer_id = {
        params = { "consumer_id" },
        query = [[ SELECT id FROM consumers WHERE id = ?; ]]
      }
    },
    __unique = {
      self = {
        params = { "username" },
        query = [[ SELECT * FROM basicauth_credentials WHERE username = ?; ]]
      }
    }
  }

  BasicAuthDAO.super.new(self, properties)
end

return BasicAuthDAO
