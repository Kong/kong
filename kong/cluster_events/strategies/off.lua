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
