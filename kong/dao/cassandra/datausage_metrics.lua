local cassandra = require "cassandra"
local BaseDao = require "kong.dao.cassandra.base_dao"
local timestamp = require "kong.tools.timestamp"

local DataUsageMetrics = BaseDao:extend()

function DataUsageMetrics:new(properties)
    self._queries = {
        increment_counter = [[ UPDATE datausage_metrics SET value = value + ? WHERE api_id = ? AND
                            identifier = ? AND
                            period_date = ? AND
                            period = ?; ]],
        select_one = [[ SELECT * FROM datausage_metrics WHERE api_id = ? AND
                      identifier = ? AND
                      period_date = ? AND
                      period = ?; ]],
        delete = [[ DELETE FROM datausage_metrics WHERE api_id = ? AND
                  identifier = ? AND
                  period_date = ? AND
                  period = ?; ]]
    }

    DataUsageMetrics.super.new(self, properties)
end

function DataUsageMetrics:increment(api_id, identifier, current_timestamp, count)
    if not count then count = 1 end
    local periods = timestamp.get_timestamps(current_timestamp)
    local batch = cassandra.BatchStatement(cassandra.batch_types.COUNTER)

    for period, period_date in pairs(periods) do
        batch:add(self._queries.increment_counter, {
            cassandra.bigint(count),
            cassandra.uuid(api_id),
            identifier,
            cassandra.timestamp(period_date),
            period
        })
    end

    return DataUsageMetrics.super._execute(self, batch)
end

function DataUsageMetrics:find_one(api_id, identifier, current_timestamp, period)
    local periods = timestamp.get_timestamps(current_timestamp)

    local metric, err = DataUsageMetrics.super._execute(self, self._queries.select_one, {
        cassandra.uuid(api_id),
        identifier,
        cassandra.timestamp(periods[period]),
        period
    })
    if err then
        return nil, err
    elseif #metric > 0 then
        metric = metric[1]
    else
        metric = nil
    end

    return metric
end

function DataUsageMetrics:delete(api_id, identifier, periods)
    error("datausage_metrics:delete() not yet implemented")
end

-- Unsuported
function DataUsageMetrics:insert()
    error("datausage_metrics:insert() not supported", 2)
end

function DataUsageMetrics:update()
    error("datausage_metrics:update() not supported", 2)
end

function DataUsageMetrics:find()
    error("datausage_metrics:find() not supported", 2)
end

function DataUsageMetrics:find_by_keys()
    error("datausage_metrics:find_by_keys() not supported", 2)
end

return DataUsageMetrics
