-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cassandra = require "cassandra"
local split     = require "kong.tools.utils".split
local sales_counters = require "kong.counters.sales.strategies.common"


local log = ngx.log
local ERR = ngx.ERR
local MONTHS_TO_REPORT    = sales_counters.MONTHS_TO_REPORT
local get_count_by_month  = sales_counters.get_count_by_month
local get_request_buckets = sales_counters.get_request_buckets
local get_year_month      = sales_counters.get_year_month

local UPDATE_STATEMENT = [[
    UPDATE license_data SET
      req_cnt = req_cnt + ?
    WHERE
      node_id = ? AND
      license_creation_date = ? AND
      year = ? AND
      month = ?
]]


local SELECT_DATA = [[
  SELECT year, month, req_cnt FROM license_data
]]


local QUERY_OPTIONS = {
  prepared = true,
}


local _M = {}
local mt = { __index = _M }


function _M:new(db)
  local self = {
    connector = db.connector,
    cluster   = db.connector.cluster,
  }

  return setmetatable(self, mt)
end


function _M:init()
  return true
end


function _M:flush_data(data)
  local date_split = split(data.license_creation_date, "-")
  local timestamp = os.time({
    year = date_split[1],
    month = date_split[2],
    day = date_split[3],
  })
  local current_year = tonumber(os.date("%Y"))
  local current_month = tonumber(os.date("%m"))

  local values = {
    cassandra.counter(data.request_count),
    cassandra.uuid(data.node_id),
    cassandra.timestamp(timestamp * 1000),
    cassandra.int(current_year),
    cassandra.int(current_month)
  }

  local _, err = self.cluster:execute(UPDATE_STATEMENT, values, QUERY_OPTIONS)
  if err then
    log(ERR, "error occurred during counters data flush: ", err)
  end
end


function _M:pull_data()
  local min_year_month = get_year_month(MONTHS_TO_REPORT)
  local res, err = self.cluster:execute(SELECT_DATA, QUERY_OPTIONS)
  if err then
    log(ERR, "error occurred during data pull: ", err)
    return nil
  end

  local count = get_count_by_month(res, min_year_month)
  local data = get_request_buckets(count)

  return data
end


return _M
