local syslog = require "kong.tools.syslog"
local lock = require "resty.lock"
local cache = require "kong.tools.database_cache"

local INTERVAL = 3600

local _M = {}

local function create_timer(at, cb)
  local ok, err = ngx.timer.at(at, cb)
  if not ok then
    ngx.log(ngx.ERR, "[reports] failed to create timer: ", err)
  end
end

local function send_ping(premature)
  local lock = lock:new("locks", {
    exptime = INTERVAL - 0.001
  })
  local elapsed = lock:lock("ping")
  if elapsed and elapsed == 0 then
    local reqs = cache.get(cache.requests_key())
    if not reqs then reqs = 0 end
    syslog.log({signal = "ping", requests=reqs})
  end
  create_timer(INTERVAL, send_ping)
end

function _M.execute()
  cache.rawset(cache.requests_key(), 0, 0) -- Initializing the counter
  create_timer(0, send_ping)
end

return _M
