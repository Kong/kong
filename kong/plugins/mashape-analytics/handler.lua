-- Analytics plugin handler.
--
-- How it works:
-- Keep track of calls made to configured APIs on a per-worker basis, using the ALF format
-- (alf_serializer.lua) and per-API buffers. `:access()` and `:body_filter()` are implemented to record some properties
-- required for the ALF entry.
--
-- When an API buffer is full (it reaches the `batch_size` configuration value or the maximum payload size), send the batch to the server.
--
-- In order to keep Analytics as real-time as possible, we also start a 'delayed timer' running in background.
-- If no requests are made during a certain period of time (the `delay` configuration value), the
-- delayed timer will fire and send the batch + flush the data, not waiting for the buffer to be full.
--
-- @see alf_serializer.lua
-- @see buffer.lua

local BasePlugin = require "kong.plugins.base_plugin"
local Buffer = require "kong.plugins.mashape-analytics.buffer"

local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data

local _alf_buffers = {} -- buffers per-api

local AnalyticsHandler = BasePlugin:extend()

function AnalyticsHandler:new()
  AnalyticsHandler.super.new(self, "mashape-analytics")
end

function AnalyticsHandler:access(conf)
  AnalyticsHandler.super.access(self)

  if conf.log_bodies then
    read_body()
    ngx.ctx.galileo = {req_body = get_body_data()}
  end
end

function AnalyticsHandler:body_filter(conf)
  AnalyticsHandler.super.body_filter(self)

  if conf.log_bodies then
    local chunk = ngx.arg[1]
    local ctx = ngx.ctx
    local res_body = ctx.galileo and ctx.galileo.res_body or ""
    res_body = res_body .. (chunk or "")
    ctx.galileo.res_body = res_body
  end
end

function AnalyticsHandler:log(conf)
  AnalyticsHandler.super.log(self)

  local ctx = ngx.ctx
  local api_id = ctx.api.id

  local buf = _alf_buffers[api_id]
  if not buf then
    buf = Buffer.new(conf)
    _alf_buffers[api_id] = buf
  end

  local req_body, res_body
  if ctx.galileo then
    req_body = ctx.galileo.req_body
    res_body = ctx.galileo.res_body
  end

  buf:add_entry(ngx, req_body, res_body)
end

return AnalyticsHandler
