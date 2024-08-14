-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

---@class util
---@field set_optional_str fun(tbl:table, key:string, value:string) @If value is non-nil, then sets the given key on tbl to value
---@field set_optional_arr fun(tbl:table, key:string, value:table)  @If value is non-nil and has elements, then sets the given key on tbl to space separate concatenation of elements

---@type util
local _M = {}


local table_concat = table.concat


function _M.set_optional_str(tbl, key, value)
  if value ~= nil then
    tbl[key] = value
  end
end

function _M.set_optional_arr(tbl, name, value)
  if (value and #value > 0) then
    tbl[name] = table_concat(value, " ")
  end
end

return _M
