-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local old_tcp_connect
local old_tcp_sslhandshake
local old_udp_setpeername

local timing


local function before_connect(self, host, port, options)
  local destination

  if string.sub(host, 1, 5) == "unix:" then
    destination = host

  else
    destination = "tcp://" .. host .. ":" .. tostring(port)
  end

  self.__kong_timing_destination__ = destination

  timing.enter_context("connections")
  timing.enter_context(destination)
  timing.enter_context("connect")
end


local function after_connect()
  timing.leave_context() -- leave connect
  timing.leave_context() -- leave destination
  timing.leave_context() -- leave connections
end


local function before_sslhandshake(self, reused_session, server_name, _ssl_verify, _send_status_req)
  timing.enter_context("connections")
  timing.enter_context(self.__kong_timing_destination__ or "unknown")
  timing.enter_context("sslhandshake")
  timing.set_context_prop("attempt_reuse_session", reused_session ~= nil)
  timing.set_context_prop("sni", server_name)
end


local function after_sslhandshake()
  timing.leave_context() -- leave sslhandshake
  timing.leave_context() -- leave destination
  timing.leave_context() -- leave connections
end


local function before_setpeername(self, host, port)
  local destination

  if string.sub(host, 1, 5) == "unix:" then
    destination = host

  else
    destination = "udp://" .. host .. ":" .. port
  end

  self.__kong_timing_destination__ = destination

  timing.enter_context("connections")
  timing.enter_context(destination)
  timing.enter_context("setpeername")
end


local function after_setpeername()
  _M.leave_context() -- leave setpeername
  _M.leave_context() -- leave destination
  _M.leave_context() -- leave connections
end


local function patched_connect(self, ...)
  before_connect(self, ...)
  local ok, err = old_tcp_connect(self, ...)
  after_connect()
  return ok, err
end


local function patched_sslhandshake(self, ...)
  before_sslhandshake(self, ...)
  local ok, err = old_tcp_sslhandshake(self, ...)
  after_sslhandshake()
  return ok, err
end


local function after_tcp(sock)
  if not old_tcp_connect then
    old_tcp_connect = sock.connect
  end

  if not old_tcp_sslhandshake then
    old_tcp_sslhandshake = sock.sslhandshake
  end

  sock.connect = patched_connect
  sock.sslhandshake = patched_sslhandshake
  return sock
end


local function patched_setpeername(self, ...)
  before_setpeername(self, ...)
  local ok, err = old_udp_setpeername(self, ...)
  after_setpeername()
  return ok, err
end


local function after_udp(sock)
  if not old_udp_setpeername then
    old_udp_setpeername = sock.setpeername
  end

  sock.setpeername = patched_setpeername
  return sock
end


function _M.register_hooks(timing_module)
  local req_dyn_hook = require("kong.dynamic_hook")

  -- creating a new TCP socket object doesn't need any arguments
  req_dyn_hook.hook_function("timing", ngx.socket, "tcp", 0, {
    afters = { after_tcp },
  })

  -- creating a new UDP socket object doesn't need any arguments
  req_dyn_hook.hook_function("timing", ngx.socket, "udp", 0, {
    afters = { after_udp },
  })

  timing = timing_module
end


return _M
