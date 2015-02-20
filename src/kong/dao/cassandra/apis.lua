local BaseDao = require "kong.dao.cassandra.base_dao"

local SCHEMA = {
  id = { type = "id" },
  name = { required = true, unique = true, queryable = true },
  public_dns = { required = true, unique = true, queryable = true,
                 regex = "(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])" },
  target_url = { required = true },
  created_at = { type = "timestamp" }
}

local Apis = BaseDao:extend()

function Apis:new(properties)
  self._schema = SCHEMA
  self._queries = {
    insert = {
      params = { "id", "name", "public_dns", "target_url", "created_at" },
      query = [[ INSERT INTO apis(id, name, public_dns, target_url, created_at)
                  VALUES(?, ?, ?, ?, ?); ]]
    },
    update = {
      params = { "name", "public_dns", "target_url", "id" },
      query = [[ UPDATE apis SET name = ?, public_dns = ?, target_url = ? WHERE id = ?; ]]
    },
    select = {
      query = [[ SELECT * FROM apis %s; ]]
    },
    select_one = {
      params = { "id" },
      query = [[ SELECT * FROM apis WHERE id = ?; ]]
    },
    delete = {
      params = { "id" },
      query = [[ DELETE FROM apis WHERE id = ?; ]]
    },
    __unique = {
      name = {
        params = { "name" },
        query = [[ SELECT id FROM apis WHERE name = ?; ]]
      },
      public_dns = {
        params = { "public_dns" },
        query = [[ SELECT id FROM apis WHERE public_dns = ?; ]]
      }
    }
  }

  Apis.super.new(self, properties)
end

return Apis
