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

local ALFBuffer = require "kong.plugins.mashape-analytics.buffer"
local BasePlugin = require "kong.plugins.base_plugin"
local ALFSerializer = require "kong.plugins.log_serializers.alf"

local ALF_BUFFERS = {} -- buffers per-api

-- A handler for delayed batch sending. When no call have been made for X seconds
-- (X being conf.delay), we send the batch to keep analytics as close to real-time
-- as possible.
local delayed_send_handler
delayed_send_handler = function(premature, conf, buffer)
  -- If the latest call was received during the wait delay, abort the delayed send and
  -- report it for X more seconds.
  if ngx.now() - buffer.latest_call < conf.delay then
    local ok, err = ngx.timer.at(conf.delay, delayed_send_handler, conf, buffer)
    if not ok then
      buffer.delayed = false -- re-enable creation of a delayed-timer for this buffer
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  else
    buffer.delayed = false
    buffer.send_batch(nil, buffer)
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

  -- Create the ALF buffer if not existing for this API
  if not ALF_BUFFERS[api_id] then
    ALF_BUFFERS[api_id] = ALFBuffer.new()
  end

  local buffer = ALF_BUFFERS[api_id]

  -- Creating the ALF
  local alf = ALFSerializer.new_alf(ngx, conf.service_token, conf.environment)

  -- Simply adding the ALF to the buffer
  local buffer_size = buffer:add_alf(alf)

  -- Keep track of the latest call for the delayed timer
  buffer.latest_call = ngx.now()

  if buffer_size >= conf.batch_size then
    -- Batch size reached, let's send the data
    local ok, err = ngx.timer.at(0, buffer.send_batch, buffer)
    if not ok then
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create batch sending timer: ", err)
    end
  elseif not buffer.delayed then
    -- Batch size not yet reached.
    -- Set a timer sending the data only in case nothing happens for awhile or if the batch_size is taking
    -- too much time to reach the limit and trigger the flush.
    local ok, err = ngx.timer.at(conf.delay, delayed_send_handler, conf, buffer)
    if ok then
      buffer.delayed = true -- Make sure only one delayed timer is ever pending for a given buffer
    else
      ngx.log(ngx.ERR, "[mashape-analytics] failed to create delayed batch sending timer: ", err)
    end
  end
end

return AnalyticsHandler
