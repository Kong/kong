-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sales_counters = require "kong.enterprise_edition.counters.sales.strategies.common"


local fmt = string.format
local log        = ngx.log
local ERR        = ngx.ERR
local MONTHS_TO_REPORT    = sales_counters.MONTHS_TO_REPORT
local get_count_by_month  = sales_counters.get_count_by_month
local get_request_buckets = sales_counters.get_request_buckets
local get_year_month      = sales_counters.get_year_month

local INSERT_DATA = [[
  INSERT INTO license_data (node_id, license_creation_date, req_cnt, year, month)
  VALUES ('%s', '%s', %d, %d, %d)
  ON CONFLICT (node_id, year, month)
  DO UPDATE SET req_cnt = license_data.req_cnt + excluded.req_cnt;
]]

local SELECT_DATA = [[
  SELECT req_cnt, year, month
  FROM license_data
  WHERE year >= %d OR year = 0;
]]


local _M = {}
local mt = { __index = _M }


function _M:new(db)
  local self = {
    connector = db.connector,
  }

  return setmetatable(self, mt)
end

function _M:init()
  return true
end


function _M:flush_data(data)
  local current_year = tonumber(os.date("%Y"))
  local current_month = tonumber(os.date("%m"))
  local values = {
    data.node_id,
    data.license_creation_date,
    data.request_count,
    current_year,
    current_month,
  }

  local _, err = self.connector:query(fmt(INSERT_DATA, unpack(values)))
  if err then
    log(ERR, "error occurred during counters data flush: ", err)
  end
end


function _M:pull_data()
  local min_year_month = get_year_month(MONTHS_TO_REPORT)
  local res, err = self.connector:query(fmt(SELECT_DATA, min_year_month.year))
  if err then
    log(ERR, "error occurred during data pull: ", err)
    return nil
  end

  local count = get_count_by_month(res, min_year_month)
  local data = get_request_buckets(count)

  return data

end


return _M
