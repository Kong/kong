-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local log        = ngx.log
local ERR        = ngx.ERR

local INSERT_DATA = [[
  INSERT INTO license_data (node_id, license_creation_date, req_cnt)
  VALUES ('%s', '%s', %d)
  ON CONFLICT (node_id) DO UPDATE SET
    req_cnt = license_data.req_cnt + excluded.req_cnt
]]

local SELECT_DATA = [[
  select * from license_data
]]

local _M = {}
local mt = { __index = _M }


function _M:new(db)
  local self = {
    connector = db.connector
  }

  return setmetatable(self, mt)
end

function _M:init()
  return true
end

function _M:flush_data(data)
  local values = {
    data.node_id,
    data.license_creation_date,
    data.request_count
  }

  local _, err = self.connector:query(fmt(INSERT_DATA, unpack(values)))

  if err then
    log(ERR, "error occurred during counters data flush: ", err)
  end
end


function _M:pull_data()
  local res, err = self.connector:query(SELECT_DATA)
  if err then
    log(ERR, "error occurred during data pull: ", err)
    return nil
  end

  return res
end


return _M
