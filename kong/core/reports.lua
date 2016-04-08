local syslog = require "kong.tools.syslog"
local cache = require "kong.tools.database_cache"
local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local unique_str = utils.random_string()
local enabled = false

local resty_lock
local status, res = pcall(require, "resty.lock")
if status then
  resty_lock = res
end

local INTERVAL = 3600

local function create_timer(at, cb)
  local ok, err = ngx.timer.at(at, cb)
  if not ok then
    ngx.log(ngx.ERR, "[reports] failed to create timer: ", err)
  end
end

local function send_ping(premature)
  if premature then return end

  local lock = resty_lock:new("reports_locks", {
    exptime = INTERVAL - 0.001
  })
  local elapsed = lock:lock("ping")
  if elapsed and elapsed == 0 then
    local reqs = cache.get(cache.requests_key())
    if not reqs then reqs = 0 end
    syslog.log({signal = "ping", requests = reqs, unique_id = unique_str, database = singletons.configuration.database})
    cache.incr(cache.requests_key(), -reqs) -- Reset counter
  end
  create_timer(INTERVAL, send_ping)
end

return {
  init_worker = function()
    if enabled then
      cache.rawset(cache.requests_key(), 0, 0) -- Initializing the counter
      create_timer(INTERVAL, send_ping)
    end
  end,
  log = function()
    if enabled then
      cache.incr(cache.requests_key(), 1)
    end
  end,
  enable = function()
    enabled = true
  end
}
