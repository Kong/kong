-- Analytics plugin handler.
--
-- How it works:
-- Keep track of calls made to configured APIs on a per-worker basis, using the ALF format
-- (alf_serializer.lua). `:access()` and `:body_filter()` are implemented to record some properties
-- required for the ALF entry.
--
-- When the buffer is full (it reaches the `batch_size` configuration value), send the batch to the server.
-- If the server doesn't accept it, don't flush the data and it'll try again at the next call.
-- If the server accepted the batch, flush the buffer.
--
-- In order to keep Analytics as real-time as possible, we also start a 'delayed timer' running in background.
-- If no requests are made during a certain period of time (the `delay` configuration value), the
-- delayed timer will fire and send the batch + flush the data, not waiting for the buffer to be full.

local http = require "resty_http"
local BasePlugin = require "kong.plugins.base_plugin"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

local ALF_BUFFER = {}
local DELAYED_LOCK = false -- careful: this will only work when lua_code_cache is on
local LATEST_CALL

local ANALYTICS_SOCKET = {
  host = "socket.analytics.mashape.com",
  port = 80,
  path = "/1.0.0/single"
}

local function send_batch(premature, conf, alf)
  -- Abort the sending if the entries are empty, maybe it was triggered from the delayed
  -- timer, but already sent because we reached the limit in a request later.
  if table.getn(alf.har.log.entries) < 1 then
    return
  end

  local message = alf:to_json_string(conf.service_token, conf.environment)

  local ok, err
  local client = http:new()
  client:set_timeout(50000) -- 5 sec

  ok, err = client:connect(ANALYTICS_SOCKET.host, ANALYTICS_SOCKET.port)
  if not ok then
    ngx.log(ngx.ERR, "[mashape-analytics] failed to connect to the socket server: "..err)
    return
  end

  local res, err = client:request({path = ANALYTICS_SOCKET.path, body = message})
  if not res then
    ngx.log(ngx.ERR, "[mashape-analytics] failed to send batch: "..err)
  elseif res.status == 200 then
    alf:flush_entries()
    ngx.log(ngx.DEBUG, string.format("[mashape-analytics] successfully saved the batch. (%s)", res.body))
  else
    ngx.log(ngx.ERR, string.format("[mashape-analytics] socket server refused the batch. Status: (%s) Error: (%s)", res.status, res.body))
  end

  -- close connection, or put it into the connection pool
  if not res or res.headers["connection"] == "close" then
    ok, err = client:close()
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to close socket: "..err)
    end
  else
    client:set_keepalive()
  end
end

-- A handler for delayed batch sending. When no call have been made for X seconds
-- (X being conf.delay), we send the batch to keep analytics as close to real-time
-- as possible.
local delayed_send_handler
delayed_send_handler = function(premature, conf, alf)
  -- If the latest call was received during the wait delay, abort the delayed send and
  -- report it for X more seconds.
  if ngx.now() - LATEST_CALL < conf.delay then
    local ok, err = ngx.timer.at(conf.delay, delayed_send_handler, conf, alf)
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  else
    DELAYED_LOCK = false -- re-enable creation of a delayed-timer
    send_batch(premature, conf, alf)
  end
end

--
--
--

local AnalyticsHandler = BasePlugin:extend()

function AnalyticsHandler:new()
  AnalyticsHandler.super.new(self, "mashape-analytics")
end

function AnalyticsHandler:access(conf)
  AnalyticsHandler.super.access(self)

  -- Retrieve and keep in memory the bodies for this request
  ngx.ctx.analytics = {
    req_body = "",
    res_body = ""
  }

  if conf.log_body then
    ngx.req.read_body()
    ngx.ctx.analytics.req_body = ngx.req.get_body_data()
  end
end

function AnalyticsHandler:body_filter(conf)
  AnalyticsHandler.super.body_filter(self)

  local chunk, eof = ngx.arg[1], ngx.arg[2]
  -- concatenate response chunks for ALF's `response.content.text`
  if conf.log_body then
    ngx.ctx.analytics.res_body = ngx.ctx.analytics.res_body..chunk
  end

  if eof then -- latest chunk
    ngx.ctx.analytics.response_received = ngx.now() * 1000
  end
end

function AnalyticsHandler:log(conf)
  AnalyticsHandler.super.log(self)

  local api_id = ngx.ctx.api.id

  -- Create the ALF if not existing for this API
  if not ALF_BUFFER[api_id] then
    ALF_BUFFER[api_id] = ALFSerializer:new_alf()
  end

  -- Simply adding the entry to the ALF
  local n_entries = ALF_BUFFER[api_id]:add_entry(ngx)

  -- Keep track of the latest call for the delayed timer
  LATEST_CALL = ngx.now()

  if n_entries >= conf.batch_size then
    -- Batch size reached, let's send the data
    local ok, err = ngx.timer.at(0, send_batch, conf, ALF_BUFFER[api_id])
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create batch sending timer: ", err)
    end
  elseif not DELAYED_LOCK then
    DELAYED_LOCK = true -- Make sure only one delayed timer is ever pending
    -- Batch size not yet reached.
    -- Set a timer sending the data only in case nothing happens for awhile or if the batch_size is taking
    -- too much time to reach the limit and trigger the flush.
    local ok, err = ngx.timer.at(conf.delay, delayed_send_handler, conf, ALF_BUFFER[api_id])
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  end
end

return AnalyticsHandler
