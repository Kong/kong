local fmt = string.format


local INSERT_DATA = [[
  INSERT INTO license_data (node_id, req_cnt)
  VALUES ('%s', %d)
  ON CONFLICT (node_id) DO UPDATE SET
    req_cnt = license_data.req_cnt + excluded.req_cnt
]]


local _M = {}
local mt = { __index = _M }


function _M:new(db)
  local self = {
    connector = db.connector
  }

  return setmetatable(self, mt)
end


function _M:flush_data(data)
  local values = {
    data.node_id,
    data.request_count
  }

  self.connector:query(fmt(INSERT_DATA, unpack(values)))
end


return _M
