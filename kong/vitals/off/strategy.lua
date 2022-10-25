-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local off = {}


local function noop()
  return true
end


local OffStrategy = {}
OffStrategy.__index = OffStrategy


OffStrategy.delete_stats = noop
OffStrategy.init = noop
OffStrategy.insert = noop
OffStrategy.insert_consumer_stats = noop
OffStrategy.insert_stats = noop
OffStrategy.insert_status_code_classes = noop
OffStrategy.insert_status_code_classes_by_workspace = noop
OffStrategy.insert_status_codes_by_consumer_and_route = noop
OffStrategy.insert_status_codes_by_route = noop
OffStrategy.insert_status_codes_by_service = noop
OffStrategy.start = noop
OffStrategy.stop = noop
OffStrategy.truncate_events = noop


function OffStrategy.should_use_polling()
  return false
end


function OffStrategy:select_interval(channels, min_at, max_at)
  return function()
  end
end


function OffStrategy:server_time()
  return ngx.now()
end


function OffStrategy:select_phone_home()
  return nil
end


function off.new(db, page_size, event_ttl)
  return setmetatable({}, OffStrategy)
end


return off
