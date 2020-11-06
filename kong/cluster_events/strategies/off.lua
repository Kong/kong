-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local off = {}


local OffStrategy = {}
OffStrategy.__index = OffStrategy


function OffStrategy.should_use_polling()
  return false
end


function OffStrategy:insert(node_id, channel, at, data, delay)
  return true
end


function OffStrategy:select_interval(channels, min_at, max_at)
  return function()
  end
end


function OffStrategy:truncate_events()
  return true
end


function OffStrategy:server_time()
  return ngx.now()
end


function off.new(db, page_size, event_ttl)
  return setmetatable({}, OffStrategy)
end


return off
