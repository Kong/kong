local RAT = require "kong.tools.request_aware_table"

local get_phase = ngx.get_phase
local kong = kong


local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}

local tab = RAT.new({})

local function access_tables()
  local query = kong.request.get_query()

  if query.clear == "true" and get_phase() == "access" then
    -- clear before access
    tab.clear()
  end

  -- write access
  tab.foo = "bar"
  tab.bar = "baz"
  -- read/write access
  tab.baz = tab.foo .. tab.bar

  if query.clear == "true" and get_phase() == "body_filter" then
    -- clear after access
    tab.clear()
  end
end

function _M:access(conf)
  access_tables()
end

function _M:header_filter(conf)
  access_tables()
end

function _M:body_filter(conf)
  access_tables()
end

return _M
