local counters_service = require("kong.counters")


local timer_at   = ngx.timer.at
local log        = ngx.log
local INFO       = ngx.INFO
local ERR        = ngx.ERR


local FLUSH_LOCK_KEY = "counters:sales:flush_lock"
local _log_prefix = "[sales counters] "


local _M = {}
local mt = { __index = _M }


local METRICS = {
  requests = "request_count"
}


local persistence_handler

persistence_handler = function(premature, self)
  if premature then
    -- we could flush counters now
    return
  end

  -- if we've drifted, get back in sync
  local delay = self.flush_interval
  local when  = delay - (ngx.now() - (math.floor(ngx.now() / delay) * delay))

  -- only adjust if we're off by 1 second or more, otherwise we spawn
  -- a gazillion timers and run out of memory.
  when = when < 1 and delay or when

  local ok, err = timer_at(when, persistence_handler, self)
  if not ok then
    return nil, "failed to start recurring vitals timer (2): " .. err
  end

  local _, err = self:flush_data()
  if err then
    log(ERR, _log_prefix, "flush_counters() threw an error: ", err)
  end
end


function _M.new(opts)
  local self = {
    list_cache     = ngx.shared.kong_counters,
    flush_interval = opts.flush_interval or 60,
    strategy = opts.strategy,
    counters = counters_service.new({
      name = "sales"
    })
  }

  self.counters:add_key(METRICS.requests)
  return setmetatable(self, mt)
end

function _M:init()
  self.counters:init()

  local delay = self.flush_interval
  local when  = delay - (ngx.now() - (math.floor(ngx.now() / delay) * delay))
  log(INFO, _log_prefix, "starting sales counters timer (1) in ", when, " seconds")

  local ok, _ = timer_at(when, persistence_handler, self)
  if ok then
    self:flush_data()
  end

  return "ok"
end

function _M:log_request()
  self.counters:increment(METRICS.requests)
end


local function merge_counter(counter_data)
  local final_counter = 0
  if counter_data then
    for _, counter in pairs(counter_data) do
      final_counter = final_counter + counter
    end
  end
  return final_counter
end


-- Acquire a lock for flushing counters to the database
function _M:flush_lock()
  local ok, err = self.list_cache:safe_add(FLUSH_LOCK_KEY, true,
    self.flush_interval - 0.01)
  if not ok then
    if err ~= "exists" then
      log(ERR, _log_prefix, "failed to acquire lock: ", err)
    end

    return false
  end

  return true
end


function _M:flush_data()
  local lock = self:flush_lock()

  if lock then
    local counters = self.counters:get_counters()

    local merged_data = {
      node_id = self.counters.node_id,
      request_count = 0
    }

    -- merge data
    if counters then
      for _, row in ipairs(counters) do
        local data = row.data
        if data then
          for _, metric_name in pairs(METRICS) do
            local cnt = merge_counter(data[metric_name])
            merged_data[metric_name] = merged_data[metric_name] + cnt
          end
        end
      end

      self.strategy:flush_data(merged_data)
    end
  end
end


return _M
