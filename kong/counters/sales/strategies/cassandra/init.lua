local cassandra = require "cassandra"


local log = ngx.log
local ERR = ngx.ERR


local UPDATE_STATEMENT = [[
    UPDATE license_data SET
      req_cnt = req_cnt + ?
    WHERE
      node_id = ?
  ]]


local _M = {}
local mt = { __index = _M }


function _M:new(db)
  local self = {
    connector = db.connector,
    cluster   = db.connector.cluster,
  }

  return setmetatable(self, mt)
end


function _M:flush_data(data)
  local values = {
    cassandra.counter(data.request_count),
    cassandra.uuid(data.node_id)
  }

  local QUERY_OPTIONS = {
    prepared = true,
  }

  local _, err = self.cluster:execute(UPDATE_STATEMENT, values, QUERY_OPTIONS)

  if err then
    log(ERR, "error occurred during counters flush in cassandra: ", err)
  end
end


return _M
