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

  self.insert_or_update_stmt = database:prepare [[
    INSERT OR REPLACE INTO metrics
      VALUES (:api_id, :application_id, :name, :timestamp,
        COALESCE(
          (SELECT value FROM metrics
            WHERE api_id = :api_id
              AND application_id = :application_id
              AND name = :name
              AND timestamp = :timestamp),
        -1) + :step);
  ]]

  self.retrieve_stmt = database:prepare [[
    SELECT * FROM metrics WHERE api_id = ?
                            AND application_id = ?
                            AND name = ?
                            AND timestamp = ?;
  ]]

  self.get_by_rowid = database:prepare [[
    SELECT * FROM metrics WHERE rowid = ?;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM metrics WHERE api_id = ?
                          AND application_id = ?
                          AND name = ?
                          AND timestamp = ?;
  ]]
end

-- @override
function Metrics:get_by_id()
 error("Metrics:get_by_id() not supported")
end

-- @override
function Metrics:get_all()
  error("Metrics:get_all() not supported")
end

-- @override
function Metrics:update()
  error("Metrics:update() not supported")
end

-- @override
function Metrics:save()
  error("Metrics:save() not supported")
end

-- @override
function Metrics:delete(api_id, application_id, name, timestamp)
  self.delete_stmt:bind_values(api_id, application_id, name, timestamp)
  return self:exec_stmt(self.delete_stmt)
end

function Metrics:increment_metric(api_id, application_id, name, timestamp, step)
  if not step then step = 1 end

  self.insert_or_update_stmt:bind_names {
      name = name,
      step = step,
      value = value,
      api_id = api_id,
      timestamp = timestamp,
      application_id = application_id
  }
  local rowid, err = self:exec_insert_stmt(self.insert_or_update_stmt)
  if err then
    return nil, err
  end

  self.get_by_rowid:bind_values(rowid)
  return self:exec_select_stmt(self.get_by_rowid)
end

function Metrics:retrieve_metric(api_id, application_id, name, timestamp)
  self.retrieve_stmt:bind_values(api_id, application_id, name, timestamp)
  return self:exec_select_stmt(self.retrieve_stmt)
end

return Metrics
