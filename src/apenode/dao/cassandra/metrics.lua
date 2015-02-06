local BaseDao = require "apenode.dao.cassandra.base_dao"
local cassandra = require "cassandra"

local Metrics = BaseDao:extend()

function Metrics:new(database)
  self._queries = {
    increment = {
      query = [[ UPDATE metrics SET value = value + 1 WHERE api_id = ? AND
                                                            identifier = ? AND
                                                            period IN ?; ]]
    },
    select = {
      query = [[ SELECT * FROM metrics WHERE api_id = ? AND
                                             identifier = ? AND
                                             period IN ?; ]]
    },
    delete = {
      query = [[ DELETE FROM metrics WHERE api_id = ? AND
                                           identifier = ? AND
                                           period IN ?; ]]
    }
  }

  Metrics.super.new(self, database)
end

function Metrics:increment(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.increment, {
    cassandra.uuid(api_id),
    identifier,
    cassandra.list(periods)
  })
end

function Metrics:find(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.select, {
    cassandra.uuid(api_id),
    identifier,
    cassandra.list(periods)
  })
end

function Metrics:delete(api_id, identifier, periods)
  return Metrics.super.execute_prepared_stmt(self, self._statements.delete, {
    cassandra.uuid(api_id),
    identifier,
    cassandra.list(periods)
  })
end

-- Unsuported
function Metrics:insert()
  error("metrics:insert() not supported")
end

function Metrics:update()
  error("metrics:update() not supported")
end

function Metrics:find_by_keys()
  error("metrics:find_by_keys() not supported")
end

function Metrics:find_one()
  error("metrics:find_one() not supported")
end

return Metrics
