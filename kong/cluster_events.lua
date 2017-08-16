local utils = require "kong.tools.utils"


local ngx_debug = ngx.config.debug
local DEBUG     = ngx.DEBUG
local ERR       = ngx.ERR
local max       = math.max
local type      = type
local pcall     = pcall
local insert    = table.insert
local ngx_log   = ngx.log
local ngx_now   = ngx.now
local timer_at  = ngx.timer.at


local NODE_ID_KEY            = "cluster_events:id"
local POLL_INTERVAL_LOCK_KEY = "cluster_events:poll_interval"
local POLL_RUNNING_LOCK_KEY  = "cluster_events:poll_running"
local CURRENT_AT_KEY         = "cluster_events:at"


local MIN_EVENT_TTL_IN_DB = 60 * 60 -- 1 hour
local PAGE_SIZE           = 100


local _init
local poll_handler


local function log(lvl, ...)
  return ngx_log(lvl, "[cluster_events] ", ...)
end


local function nbf_cb_handler(premature, cb, row)
  if premature then
    return
  end

  cb(row.data)
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

  if not opts.dao then
    return error("opts.dao is required")
  end

  -- strategy selection

  local strategy
  local poll_interval = max(opts.poll_interval or 5, 0)
  local poll_offset   = max(opts.poll_offset   or 0, 0)

  do
    local db_strategy
    local dao_factory = opts.dao

    if dao_factory.db_type == "cassandra" then
      db_strategy = require "kong.cluster_events.strategies.cassandra"

    elseif dao_factory.db_type == "postgres" then
      db_strategy = require "kong.cluster_events.strategies.postgres"

    else
      return error("no cluster_events strategy for " ..
                   dao_factory.db_type)
    end

    local event_ttl_in_db = max(poll_offset * 10, MIN_EVENT_TTL_IN_DB)

    strategy = db_strategy.new(dao_factory, PAGE_SIZE, event_ttl_in_db)
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
  }

  -- set current time (at)

  local ok, err = self.shm:safe_set(CURRENT_AT_KEY, ngx_now())
  if not ok then
    return nil, "failed to set 'at' in shm: " .. err
  end

  -- set node id (uuid)

  ok, err = self.shm:safe_add(NODE_ID_KEY, utils.uuid())
  if not ok and err ~= "exists" then
    return nil, "failed to set 'node_id' in shm: " .. err
  end

  self.node_id, err = self.shm:get(NODE_ID_KEY)
  if err then
    return nil, "failed to get 'node_id' in shm: " .. err
  end

  if not self.node_id then
    return nil, "no 'node_id' set in shm"
  end

  if ngx_debug and opts.node_id then
    self.node_id = opts.node_id
  end

  _init = true

  return setmetatable(self, mt)
end


function _M:broadcast(channel, data, nbf)
  if type(channel) ~= "string" then
    return nil, "channel must be a string"
  end

  if type(data) ~= "string" then
    return nil, "data must be a string"
  end

  if nbf and type(nbf) ~= "number" then
    return nil, "nbf must be a number"
  end

  -- insert event row

  --log(DEBUG, "broadcasting on channel: '", channel, "' data: ", data,
  --           " with nbf: ", nbf and nbf or "none")

  local ok, err = self.strategy:insert(self.node_id, channel, ngx_now(), data, nbf)
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

  if not self.polling and start_polling then
    -- start recurring polling timer

    local ok, err = timer_at(self.poll_interval, poll_handler, self)
    if not ok then
      return nil, "failed to start polling timer: " .. err
    end

    self.polling = true
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

  local max_at = ngx_now()

  log(DEBUG, "polling events from: ", min_at, " to: ", max_at)

  for rows, err, page in self.strategy:select_interval(self.channels, min_at, max_at) do
    if err then
      return nil, "failed to retrieve events from DB: " .. err
    end

    if page == 1 then
      local ok, err = self.shm:safe_set(CURRENT_AT_KEY, max_at)
      if not ok then
        return nil, "failed to set 'at' in shm: " .. err
      end
    end

    for i = 1, #rows do
      local row = rows[i]

      if row.node_id ~= self.node_id then
        local ran, err = self.events_shm:get(row.id)
        if err then
          return nil, "failed to probe if event ran: " .. err
        end

        if not ran then
          log(DEBUG, "new event (channel: '", row.channel, "') data: '",
                     row.data, "' nbf: '", row.nbf or "none", "'")

          local exptime = self.poll_interval + self.poll_offset

          -- mark as ran before running in case of long-running callbacks
          local ok, err = self.events_shm:set(row.id, true, exptime)
          if not ok then
            return nil, "failed to mark event as ran: " .. err
          end

          local cbs = self.callbacks[row.channel]
          if cbs then
            for j = 1, #cbs do
              if not row.nbf then
                -- unique callback run without delay
                local ok, err = pcall(cbs[j], row.data)
                if not ok and not ngx_debug then
                  log(ERR, "callback threw an error: ", err)
                end

              else
                -- unique callback run after some delay
                local delay = max(row.nbf - ngx_now(), 0)

                log(DEBUG, "delaying nbf event by ", delay, "s")

                local ok, err = timer_at(delay, nbf_cb_handler, cbs[j], row)
                if not ok then
                  log(ERR, "failed to schedule nbf event timer: ", err)
                end
              end
            end
          end
        end
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
      log(ERR, "failed to start recurring polling timer: ", err)
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
    log(ERR, "failed to start recurring polling timer: ", err)
  end
end


return _M
