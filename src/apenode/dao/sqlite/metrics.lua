local BaseDao = require "apenode.dao.sqlite.base_dao"

local Metrics = {}
Metrics.__index = Metrics

setmetatable(Metrics, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Metrics:_init(database)
  BaseDao:_init(database)

  self.insert_stmt = database:prepare [[
    INSERT INTO metrics(api_id,
                        account_id,
                        name,
                        value,
                        timestamp)
    VALUES(:api_id,
           :account_id,
           :name,
           :value,
           :timestamp);
  ]]

  self.update_stmt = database:prepare [[
    UPDATE metrics
    SET api_id = :api_id,
        account_id = :account_id,
        name = :name,
        value = :value,
        timestamp = :timestamp
    WHERE id = :id;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM metrics WHERE id = ?;
  ]]

  self.select_count_stmt = database:prepare [[
    SELECT COUNT(*) FROM metrics;
  ]]

  self.select_all_stmt = database:prepare [[
    SELECT * FROM metrics LIMIT :page, :size;
  ]]

  self.select_by_id_stmt = database:prepare [[
    SELECT * FROM metrics WHERE id = ?;
  ]]
end

function Metrics:increment_metric(api_id, account_id, name, value)

end

function Metrics:retrieve_metric(api_id, account_id, name, timestamp)

end

return Metrics
