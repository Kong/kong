local RAT = require "kong.tools.request_aware_table"

local kong = kong
local tab

local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}

local function access_table()
  -- write access
  tab.foo = "bar"
  tab.bar = "baz"
  -- read/write access
  tab.baz = tab.foo .. tab.bar
end


function _M:access(conf)
  local query = kong.request.get_query()
  if query.new_tab == "true" then
    -- new table
    tab = RAT.new()
  end

  -- access multiple times during same request
  access_table()
  access_table()
  access_table()

  if query.clear == "true" then
    -- clear table
    tab:clear()
  end
end


return _M
