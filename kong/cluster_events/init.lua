local ngx_debug = ngx.config.debug
local DEBUG     = ngx.DEBUG
local ERR       = ngx.ERR
local CRIT      = ngx.CRIT
local max       = math.max
local type      = type
local error     = error
local pcall     = pcall
local insert    = table.insert
local ngx_log   = ngx.log
local ngx_now   = ngx.now
local timer_at  = ngx.timer.at
local knode     = (kong and kong.node) and kong.node or
                  require "kong.pdk.node".new()


local POLL_INTERVAL_LOCK_KEY = "cluster_events:poll_interval"
local POLL_RUNNING_LOCK_KEY  = "cluster_events:poll_running"
local CURRENT_AT_KEY         = "cluster_events:at"


local MIN_EVENT_TTL_IN_DB = 60 * 60 -- 1 hour
local PAGE_SIZE           = 1000


local _init
local poll_handler


local function log(lvl, ...)
  return ngx_log(lvl, "[cluster_events] ", ...)
end


local function nbf_cb_handler(premature, cb, data)
  if premature then
    return
  end

  cb(data)
end


-- module


local _M = {}
local mt = { __index = _M }


function _M.new(opts)
  if ngx.get_phase() ~= "init_worker" and ngx.get_phase() ~= "timer" then
    return error("kong.cluster_events must be created during init_worker phase")
  end

  if not ngx_debug and _init then
    return error("kong.cluster_events was already instantiated")
  end

  -- opts validations

  opts = opts or {}

  if opts.poll_interval and type(opts.poll_interval) ~= "number" then
    return error("opts.poll_interval must be a number")
  end

  if opts.poll_offset and type(opts.poll_offset) ~= "number" then
    return error("opts.poll_offset must be a number")
  end

  if not opts.db then
    return error("opts.db is required")
  end

  -- strategy selection

  local strategy
  local poll_interval = max(opts.poll_interval or 5, 0)
  local poll_offset   = max(opts.poll_offset   or 0, 0)

  do
    local db_strategy

    if opts.db.strategy == "cassandra" then
      db_strategy = require "kong.cluster_events.strategies.cassandra"

    elseif opts.db.strategy == "postgres" then
      db_strategy = require "kong.cluster_events.strategies.postgres"

    elseif opts.db.strategy == "off" then
      db_strategy = require "kong.cluster_events.strategies.off"

    else
      return error("no cluster_events strategy for " ..
                   opts.db.strategy)
    end

    local event_ttl_in_db = max(poll_offset * 10, MIN_EVENT_TTL_IN_DB)

    strategy = db_strategy.new(opts.db, PAGE_SIZE, event_ttl_in_db)
  end

  -- instantiation

  local self      = {
    shm           = ngx.shared.kong,
    events_shm    = ngx.shared.kong_cluster_events,
    strategy      = strategy,
    poll_interval = poll_interval,
    poll_offset   = poll_offset,
    node_id       = nil,
    polling       = false,
    channels      = {},
    callbacks     = {},
    use_polling   = strategy:should_use_polling(),
  }

  -- set current time (at)

  local now = strategy:server_time() or ngx_now()
  local ok, err = self.shm:safe_set(CURRENT_AT_KEY, now)
  if not ok then
    return nil, "failed to set 'at' in shm: " .. err
  end

  -- set node id (uuid)

  self.node_id, err = knode.get_id()
  if not self.node_id then
    return nil, err
  end

  if ngx_debug and opts.node_id then
    self.node_id = opts.node_id
  end

  _init = true

  return setmetatable(self, mt)
end


function _M:broadcast(channel, data, delay)
  if type(channel) ~= "string" then
    return nil, "channel must be a string"
  end

  if type(data) ~= "string" then
    return nil, "data must be a string"
  end

  if delay and type(delay) ~= "number" then
    return nil, "delay must be a number"
  end

  -- insert event row

  --log(DEBUG, "broadcasting on channel: '", channel, "' data: ", data,
  --           " with delay: ", delay and delay or "none")

  local ok, err = self.strategy:insert(self.node_id, channel, nil, data, delay)
  if not ok then
    return nil, err
  end

  return true
end


function _M:subscribe(channel, cb, start_polling)
  if type(channel) ~= "string" then
    return error("channel must be a string")
  end

  if type(cb) ~= "function" then
    return error("callback must be a function")
  end

  if not self.callbacks[channel] then
    self.callbacks[channel] = { cb }

    insert(self.channels, channel)

  else
    insert(self.callbacks[channel], cb)
  end

  if start_polling == nil then
    start_polling = true
  end

  if not self.polling and start_polling and self.use_polling then
    -- start recurring polling timer

    local ok, err = timer_at(self.poll_interval, poll_handler, self)
    if not ok then
      return nil, "failed to start polling timer: " .. err
    end

    self.polling = true
  end

  return true
end


local function process_event(self, row, local_start_time)
  if row.node_id == self.node_id then
    return true
  end

  local ran, err = self.events_shm:get(row.id)
  if err then
    return nil, "failed to probe if event ran: " .. err
  end

  if ran then
    return true
  end

  log(DEBUG, "new event (channel: '", row.channel, "') data: '", row.data,
             "' nbf: '", row.nbf or "none", "'")

  local exptime = self.poll_interval + self.poll_offset

  -- mark as ran before running in case of long-running callbacks
  local ok, err = self.events_shm:set(row.id, true, exptime)
  if not ok then
    return nil, "failed to mark event as ran: " .. err
  end

  local cbs = self.callbacks[row.channel]
  if not cbs then
    return true
  end

  for j = 1, #cbs do
    if not row.nbf then
      -- unique callback run without delay
      local ok, err = pcall(cbs[j], row.data)
      if not ok and not ngx_debug then
        log(ERR, "callback threw an error: ", err)
      end

    else
      -- unique callback run after some delay
      local now = row.now + max(ngx_now() - local_start_time, 0)
      local delay = max(row.nbf - now, 0)

      log(DEBUG, "delaying nbf event by ", delay, "s")

      local ok, err = timer_at(delay, nbf_cb_handler, cbs[j], row.data)
      if not ok then
        log(ERR, "failed to schedule nbf event timer: ", err)
      end
    end
  end

  return true
end


local function poll(self)
  -- get events since last poll

  local min_at, err = self.shm:get(CURRENT_AT_KEY)
  if err then
    return nil, "failed to retrieve 'at' in shm: " .. err
  end

  if not min_at then
    return nil, "no 'at' in shm"
  end

  -- apply grace period

  min_at = min_at - self.poll_offset - 0.001

  log(DEBUG, "polling events from: ", min_at)

  for rows, err, page in self.strategy:select_interval(self.channels, min_at) do
    if err then
      return nil, "failed to retrieve events from DB: " .. err
    end

    local count = #rows

    if page == 1 and rows[1].now then
      local ok, err = self.shm:safe_set(CURRENT_AT_KEY, rows[1].now)
      if not ok then
        return nil, "failed to set 'at' in shm: " .. err
      end
    end

    local local_start_time = ngx_now()
    for i = 1, count do
      local ok, err = process_event(self, rows[i], local_start_time)
      if not ok then
        return nil, err
      end
    end
  end

  return true
end


if ngx_debug then
  _M.poll = poll
end


local function get_lock(self)
  -- check if a poll is not currently running, to ensure we don't start
  -- another poll while a worker is still stuck in its own polling (in
  -- case it is being slow)
  -- we still add an exptime to this lock in case something goes horribly
  -- wrong, to ensure other workers can poll new events
  -- a poll cannot take more than max(poll_interval * 5, 10) -- 10s min
  local ok, err = self.shm:safe_add(POLL_RUNNING_LOCK_KEY, true,
                                    max(self.poll_interval * 5, 10))
  if not ok then
    if err ~= "exists" then
      log(ERR, "failed to acquire poll_running lock: ", err)
    end
    -- else
    --   log(DEBUG, "failed to acquire poll_running lock: ",
    --              "a worker still holds the lock")

    return false
  end

  if self.poll_interval > 0.001 then
    -- check if interval of `poll_interval` has elapsed already, to ensure
    -- we do not run the poll when a previous poll was quickly executed, but
    -- another worker got the timer trigger a bit too late.
    ok, err = self.shm:safe_add(POLL_INTERVAL_LOCK_KEY, true,
                                self.poll_interval - 0.001)
    if not ok then
      if err ~= "exists" then
        log(ERR, "failed to acquire poll_interval lock: ", err)
      end
      -- else
      --   log(DEBUG, "failed to acquire poll_interval lock: ",
      --              "not enough time elapsed since last poll")

      self.shm:delete(POLL_RUNNING_LOCK_KEY)

      return false
    end
  end

  return true
end


poll_handler = function(premature, self)
  if premature or not self.polling then
    -- set self.polling to false to stop a polling loop
    return
  end

  if not get_lock(self) then
    local ok, err = timer_at(self.poll_interval, poll_handler, self)
    if not ok then
      log(CRIT, "failed to start recurring polling timer: ", err)
    end

    return
  end

  -- single worker

  local pok, perr, err = pcall(poll, self)
  if not pok then
    log(ERR, "poll() threw an error: ", perr)

  elseif not perr then
    log(ERR, "failed to poll: ", err)
  end

  -- unlock

  self.shm:delete(POLL_RUNNING_LOCK_KEY)

  local ok, err = timer_at(self.poll_interval, poll_handler, self)
  if not ok then
    log(CRIT, "failed to start recurring polling timer: ", err)
  end
end


return _M
