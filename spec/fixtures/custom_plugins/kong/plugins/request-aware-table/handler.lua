local RAT = require "kong.tools.request_aware_table"

local get_phase = ngx.get_phase
local ngx = ngx
local kong = kong


local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}

local checks_tab = RAT.new({}, "on")
local no_checks_tab = RAT.new({}, "off")

local function access_tables()
  local query = kong.request.get_query()
  local tab

  if query.checks ~= "false" then
    tab = checks_tab
  else
    tab = no_checks_tab
  end

  if query.clear == "true" and get_phase() == "access" then
    tab.clear()
  end

  -- write access
  tab.foo = "bar"
  -- read access
  ngx.log(ngx.DEBUG, "accessing to tab.foo" .. tab.foo)

  if query.clear == "true" and get_phase() == "body_filter" then
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
