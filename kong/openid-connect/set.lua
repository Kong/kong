-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local array  = require "kong.openid-connect.array"


local ipairs = ipairs


local set    = { has = array.has, remove = array.remove }


function set.new(init, defaults)
  local arr = array.new(init, defaults)
  local hsh = {}
  local res = {}
  local i   = 0

  for _,v in ipairs(arr) do
    if not hsh[v] then
      res[#res+1] = v
      hsh[v] = true
      i = i + 1
    end
  end

  return res, i
end


return set
