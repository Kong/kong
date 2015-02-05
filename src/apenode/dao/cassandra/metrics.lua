local BaseDao = require "apenode.dao.cassandra.base_dao"
local cassandra = require "cassandra"

local AVAILABLE_PERIODS = {
  second = true,
  minute = true,
  hour = true,
  day = true,
  month = true,
  year = true
}

local SCHEMA = {
  api_id = { type = "id", required = true, },
  identifier = { required = true },
  periods = { required = true }
}

local Metrics = BaseDao:extend()

function Metrics:new(database)
  self._schema = SCHEMA
  self._queries = {
    increment = {
      params = { "api_id", "identifier", "periods" },
      query = [[ UPDATE metrics SET value = value + 1 WHERE api_id = ? AND
                                                            identifier = ? AND
                                                            period IN ?; ]]
    },
    select = {
      params = { "api_id", "identifier", "periods" },
      query = [[ SELECT * FROM metrics WHERE api_id = ? AND
                                             identifier = ? AND
                                             period IN ?; ]]
    },
    delete = {
      params = { "api_id", "identifier", "periods" },
      query = [[ DELETE FROM metrics WHERE api_id = ? AND
                                           identifier = ? AND
                                           period IN ?; ]]
    }
  }

  Metrics.super.new(self, database)
end

function Metrics:increment(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.increment, {
    api_id = api_id,
    identifier = identifier,
    periods = cassandra.list(periods)
  })
end

function Metrics:find(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.select, {
    api_id = api_id,
    identifier = identifier,
    periods = cassandra.list(periods)
  })
end

function Metrics:delete(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.delete, {
    api_id = api_id,
    identifier = identifier,
    periods = cassandra.list(periods)
  })
end

return Metrics
