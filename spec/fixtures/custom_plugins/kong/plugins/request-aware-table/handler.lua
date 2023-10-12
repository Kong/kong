-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
    ngx.exit(200)
  end

  if query.clear == "true" then
    -- clear table
    tab:clear()
    ngx.exit(200)
  end

  -- access multiple times during same request
  for _ = 1, 3 do
    access_table()
  end
end


return _M
