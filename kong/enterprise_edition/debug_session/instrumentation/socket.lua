-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local latency_metrics = require "kong.enterprise_edition.debug_session.latency_metrics"
local time_ns = require "kong.tools.time".time_ns

local fmt = string.format

local SPAN_NAME = "kong.io.socket"
local CONNECT_SPAN_NAME = fmt("%s.connect", SPAN_NAME)
local SSLHANDSHAKE_SPAN_NAME = fmt("%s.sslhandshake", SPAN_NAME)
local SEND_SPAN_NAME = fmt("%s.send", SPAN_NAME)
local RECEIVE_SPAN_NAME = fmt("%s.receive", SPAN_NAME)
local SPAN_KIND_CLIENT = 3

local _M = {}

local old_tcp_connect
local old_tcp_sslhandshake
local old_tcp_send
local old_tcp_receive
local tracer
local instrum

local function initialized()
  return tracer ~= nil and instrum ~= nil
end

local function patched_connect(self, ...)
  if not initialized() then
    return old_tcp_connect(self, ...)
  end

  if not instrum.is_valid_phase() then
    return old_tcp_connect(self, ...)
  end

  if instrum.should_skip_instrumentation(instrum.INSTRUMENTATIONS.io) then
    return old_tcp_connect(self, ...)
  end

  local span = tracer.start_span(CONNECT_SPAN_NAME, {
    span_kind = SPAN_KIND_CLIENT,
  })
  if not span then
    return old_tcp_connect(self, ...)
  end
  local start_time = time_ns()
  local ok, err = old_tcp_connect(self, ...)
  local end_time = time_ns()
  span:finish()
  local m_ok, m_err = latency_metrics.add("socket_total_time", (end_time - start_time) / 1e6)
  if not m_ok then
    ngx.log(ngx.ERR, "failed to add socket total time metric: ", m_err)
  end
  return ok, err
end


local function patched_sslhandshake(self, ...)
  if not initialized() then
    return old_tcp_sslhandshake(self, ...)
  end

  if not instrum.is_valid_phase() then
    return old_tcp_sslhandshake(self, ...)
  end

  if instrum.should_skip_instrumentation(instrum.INSTRUMENTATIONS.io) then
    return old_tcp_sslhandshake(self, ...)
  end

  local span = tracer.start_span(SSLHANDSHAKE_SPAN_NAME, {
    span_kind = SPAN_KIND_CLIENT,
  })
  if not span then
    return old_tcp_sslhandshake(self, ...)
  end
  local start_time = time_ns()
  local ok, err = old_tcp_sslhandshake(self, ...)
  local end_time = time_ns()
  span:finish()
  local m_ok, m_err = latency_metrics.add("socket_total_time", (end_time - start_time) / 1e6)
  if not m_ok then
    ngx.log(ngx.ERR, "failed to add socket total time metric: ", m_err)
  end
  return ok, err
end

local function patched_send(self, ...)
  if not initialized() then
    return old_tcp_send(self, ...)
  end

  if not instrum.is_valid_phase() then
    return old_tcp_send(self, ...)
  end

  if instrum.should_skip_instrumentation(instrum.INSTRUMENTATIONS.io) then
    return old_tcp_send(self, ...)
  end

  local span = tracer.start_span(SEND_SPAN_NAME, {
    span_kind = SPAN_KIND_CLIENT,
  })
  if not span then
    return old_tcp_send(self, ...)
  end
  local start_time = time_ns()
  local bytes, err = old_tcp_send(self, ...)
  local end_time = time_ns()
  span:finish()

  local m_ok, m_err = latency_metrics.add("socket_total_time", (end_time - start_time) / 1e6)
  if not m_ok then
    ngx.log(ngx.ERR, "failed to add socket total time metric: ", m_err)
  end

  return bytes, err
end

local function patch_receive(self, ...)
  if not initialized() then
    return old_tcp_receive(self, ...)
  end

  if not instrum.is_valid_phase() then
    return old_tcp_receive(self, ...)
  end

  if instrum.should_skip_instrumentation(instrum.INSTRUMENTATIONS.io) then
    return old_tcp_receive(self, ...)
  end

  local span = tracer.start_span(RECEIVE_SPAN_NAME, {
    span_kind = SPAN_KIND_CLIENT,
  })
  if not span then
    return old_tcp_receive(self, ...)
  end
  local start_time = time_ns()
  local data, err, partial = old_tcp_receive(self, ...)
  local end_time = time_ns()
  span:finish()

  local m_ok, m_err = latency_metrics.add("socket_total_time", (end_time - start_time) / 1e6)
  if not m_ok then
    ngx.log(ngx.ERR, "failed to add socket total time metric: ", m_err)
  end

  return data, err, partial
end


local function after_tcp(sock)
  if not old_tcp_connect then
    old_tcp_connect = sock.connect
  end

  if not old_tcp_sslhandshake then
    old_tcp_sslhandshake = sock.sslhandshake
  end

  if not old_tcp_send then
    old_tcp_send = sock.send
  end

  if not old_tcp_receive then
    old_tcp_receive = sock.receive
  end

  sock.receive = patch_receive
  sock.connect = patched_connect
  sock.sslhandshake = patched_sslhandshake
  sock.send = patched_send
  return sock
end

function _M.instrument()
  local req_dyn_hook = require("kong.dynamic_hook")

  -- creating a new TCP socket object doesn't need any arguments
  req_dyn_hook.hook_function("active-tracing", ngx.socket, "tcp", 0, {
    afters = { after_tcp },
  })
end

function _M.init(opts)
  tracer = opts.tracer
  instrum = opts.instrum
end


-- in ms
function _M.get_total_time()
  local latency, err = latency_metrics.get("socket_total_time")
  if not latency then
    ngx.log(ngx.ERR, "failed to get socket total time metric: ", err)
    return
  end
  return latency
end

return _M
