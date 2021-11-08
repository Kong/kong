-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jq = require "resty.jq"
local lrucache = require "resty.lrucache"


local LRU = lrucache.new(1000)


return function(program)
  local jqp = LRU:get(program)
  if not jqp then
    jqp = jq.new()
    local ok, err = jqp:compile(program)
    if not ok or err then
      return nil, err
    end
    LRU:set(program, jqp)
  end

  return jqp, nil
end
