-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.enterprise_edition.debug_session.utils"
local time_ns = require "kong.tools.time".time_ns

local fmt = string.format
local get_ctx_key = utils.get_ctx_key

local SPAN_NAME = "kong.io.socket"
local CONNECT_SPAN_NAME = fmt("%s.connect", SPAN_NAME)
local SSLHANDSHAKE_SPAN_NAME = fmt("%s.sslhandshake", SPAN_NAME)
local SEND_SPAN_NAME = fmt("%s.send", SPAN_NAME)
local RECEIVE_SPAN_NAME = fmt("%s.receive", SPAN_NAME)
local SPAN_KIND_CLIENT = 3
local SOCKET_TOTAL_TIME_CTX_KEY = get_ctx_key("socket_total_time")

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
  ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] = (ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] or 0) + (end_time - start_time)
  return ok, err
end


local function patched_sslhandshake(self, ...)
  if not initialized() then
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
  ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] = (ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] or 0) + (end_time - start_time)
  return ok, err
end

local function patched_send(self, ...)
  if not initialized() then
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
  ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] = (ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] or 0) + (end_time - start_time)
  return bytes, err
end

local function patch_receive(self, ...)
  if not initialized() then
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
  ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] = (ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] or 0) + (end_time - start_time)
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
  return ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] and ngx.ctx[SOCKET_TOTAL_TIME_CTX_KEY] / 1e6 or 0
end

return _M
