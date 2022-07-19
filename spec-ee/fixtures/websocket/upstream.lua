-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson      = require "cjson"
local ws_server  = require "resty.websocket.server"
local utils      = require "kong.tools.utils"
local const      = require "spec-ee.fixtures.websocket.constants"

---
-- WebSocket mock upstream fixture
--
-- # Features
--
-- ## echo server
--
-- You send it, it sends it back! Only exceptions to this are:
--
-- * ping: it responds with a pong
-- * pong: it does nothing but emit a log entry
--
--
-- ## session server
--
-- This allows you to use two websocket clients to emulate both sides of a
-- client <-> upstream WS session:
--
-- 1. Connect a WS client to `/session/listen`
--   * x-mock-websocket-request-id response header from step 1 contains a UUID
--   * this is the "upstream" WS connection
-- 2. Connect another WS client to `/session/client?session=$ID` using the UUID
--    from step #1
--   * this is the "client" WS connection
-- 3. Call `recv_frame()` with the upstream WS client:
--   * expect a text frame
--   * text frame contains a json blob containing the client request details
-- 4. Messages sent by each WS client are forwarded across shared memory
--
-- For convenience, `spec-ee.fixtures.websocket.session` takes care of all this
-- setup work for you.

local _M = {}

local fmt = string.format
local ngx = ngx
local req = ngx.req
local var = ngx.var
local header = ngx.header
local log = ngx.log
local sleep = ngx.sleep
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local kill = ngx.thread.kill
local on_abort = ngx.on_abort
local encode = cjson.encode
local decode = cjson.decode
local find = string.find
local ngx_now = ngx.now
local update_time = ngx.update_time
local min = math.min

local INFO = ngx.INFO
local NOTICE = ngx.NOTICE
local WARN = ngx.WARN
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG


local HEADERS = const.headers
local OPCODES = const.opcode

local shm = assert(ngx.shared.kong_test_websocket_fixture,
                   "missing 'kong_test_websocket_fixture' shm declaration")


local READ_TIMEOUT = 5
local IDLE_TIMEOUT = 5
local SESSION_TIMEOUT = 30
local MAX_STEP = 0.5

local function exit(status, body)
  if ngx.get_phase() == "log" then
    error(fmt("tried to call ngx.exit() in log phase: %s, status: %s",
          body or "unknown", status))
  end

  if status == 444 then
    return ngx.exit(444)
  end

  ngx.status = status
  header["content-type"] = "application/json"
  if type(body) == "table" then
    body = cjson.encode(body)
  end
  ngx.say(body)
  return ngx.exit(0)
end

local function substr(subj, s)
  return type(subj) == "string"
         and find(subj, s, nil, true)
end

local function is_timeout(err)
  return substr(err, "timeout")
end

local function is_closed(err)
  return substr(err, "closed")
end

local function is_fin(err)
  return err ~= "again"
end

local function is_client_abort(err)
  return substr(err, "client aborted")
end

local function is_reset(err)
  return substr(err, "connection reset by peer")
end

local function now()
  update_time()
  return ngx_now()
end

---
-- Some of our test cases cover things like "what happens when the NGINX worker
-- is exiting?" Delaying the exit event here gives things a grace period so
-- that our tests don't contend with the lifetime of the "upstream"
local exiting
do
  local worker_exiting = ngx.worker.exiting
  local exited
  local timeout = 1

  function exiting()
    if not worker_exiting() then
      return false
    end

    exited = exited or now()

    local delay = now() - exited

    if delay > timeout then
      log(INFO, "delayed exit event by ", delay " seconds")
      return true
    end

    return false
  end
end

local function request_infos()
  ---@class ws.request.info
  local info = {
    url                = fmt("%s://%s:%s%s",
                             var.scheme, var.host,
                             var.server_port,
                             var.request_uri),
    headers            = req.get_headers(0),
    headers_raw        = req.get_headers(0, true),
    query              = req.get_uri_args(0),
    method             = req.get_method(),
    uri                = var.uri,
    host               = var.host,
    hostname           = var.hostname,
    https              = var.https,
    scheme             = var.scheme,
    is_args            = var.is_args,
    server_addr        = var.server_addr,
    server_port        = var.server_port,
    server_name        = var.server_name,
    server_protocol    = var.server_protocol,
    remote_addr        = var.remote_addr,
    remote_port        = var.remote_port,
    realip_remote_addr = var.realip_remote_addr,
    realip_remote_port = var.realip_remote_port,
    binary_remote_addr = var.binary_remote_addr,
    request            = var.request,
    request_uri        = var.request_uri,
    request_time       = var.request_time,
    request_length     = var.request_length,
    bytes_received     = var.bytes_received,
    ssl_client_s_dn    = var.ssl_client_s_dn,
    ssl_server_name    = var.ssl_server_name,
  }
  return info
end


local function response_infos()
  ---@class ws.response.info
  local info = {
    status = ngx.status,
    headers = ngx.resp.get_headers(0),
  }
  return info
end


local NS = {
  STATE = "state",
  SESSION = "session",
  HANDSHAKE = "handshake",
  CLIENT = "client",
  UPSTREAM = "upstream",
}

local PEER = setmetatable({
  [NS.CLIENT] = NS.UPSTREAM,
  [NS.UPSTREAM] = NS.CLIENT,
}, {
  __index = function(_, k)
    error("unknown role: " .. tostring(k))
  end
})

local function make_key(ns, id)
  return ns .. "/" .. id
end

local function shm_push(ns, id, data)
  local key = make_key(ns, id)
  local ok, err = shm:rpush(key, data)
  if not ok then
    log(ERR, "failed writing data to shm: ", err)
    return exit(444)
  end
end

local function shm_pop(ns, id)
  local key = make_key(ns, id)
  local value, err = shm:lpop(key)

  if err ~= nil then
    log(ERR, "failed LPOP from ", key, ": ", err)
    return exit(444)
  end

  return value
end

local function shm_get(ns, id)
  local key = make_key(ns, id)
  local value, err = shm:get(key)

  if err then
    log(ERR, "error while reading ", key, ": ", err)
    return exit(444)
  end

  return value, err
end

local function shm_read(ns, id, method, timeout)
  timeout = timeout or READ_TIMEOUT
  local step = 0.01
  local waited = 0
  local start = now()

  local get = method == "get" and shm_get or shm_pop

  while true do
    if exiting() then
      return nil, "exiting"
    end

    local data = get(ns, id)

    if data then
      return data

    elseif waited >= timeout then
      break
    end

    sleep(step)
    waited = now() - start
    step = min(step * 1.25, MAX_STEP)
  end

  return nil, "timeout"
end

local function shm_add(ns, id, value, ttl)
  ttl = ttl or READ_TIMEOUT
  local key = make_key(ns, id)
  local ok, err = shm:add(key, value, ttl)
  if not ok then
    log(ERR, "failed storing ", key, " to shm: ", err)
    return exit(444)
  end
end

local function shm_set(ns, id, state)
  local key = make_key(ns, id)
  local ok, err = shm:set(key, state, SESSION_TIMEOUT)
  if not ok then
    log(ERR, "failed shm:set ", key, ": ", err)
    return exit(444)
  end
end

local STATE = {
  LISTEN  = 1,
  CONNECT = 2,
  ACCEPT  = 3,
  PROXY   = 4,
  CLOSING = 5,
  ABORT   = 6,
  CLOSED  = 7,
}

local EOF = "eof"


local function shm_transition(id, state, last)
  local current = shm_get(NS.STATE, id)

  if last then
    assert(current == last, fmt("current state (%s) does not match expected (%s)",
                                current, last))
    assert(state > current, fmt("invalid state change %s => %s", current, state))
  else
    current = current or 0
  end

  local diff = state - current
  if diff == 0 then return end

  local key = make_key(NS.STATE, id)
  local new, err = shm:incr(key, diff)
  assert(new ~= nil, fmt("state change shm operation failed: %s", err))
  assert(new == state, fmt("state change %s => %s resulted in %s", current, state, new))
end


local function shm_await_state(id, state, timeout)
  timeout = timeout or IDLE_TIMEOUT
  local step = 0.01
  local waited = 0
  local start = now()

  local init = shm_get(NS.STATE, id)

  while true do
    if exiting() then
      return nil, "exiting"
    end

    local cur = shm_get(NS.STATE, id)

    if cur == state then
      log(DEBUG, fmt("waited %s seconds for state transition %s => %s",
                     waited, init, state))
      return true

    elseif cur and type(cur) ~= "number" then
      log(ERR, "invalid ", NS.STATE, " value: ", cur)
      break

    elseif cur and cur > state then
      log(ERR, NS.STATE, " is past expected: ", cur)
      break

    elseif waited >= timeout then
      break
    end

    sleep(step)
    waited = now() - start
    step = min(step * 1.25, MAX_STEP)
  end

  log(ERR, "awaiting state change to ", state, " failed")
  return exit(444)
end


local session = {
  accept = function(id, timeout)
    log(DEBUG, "session upstream LISTEN: ", id)
    shm_add(NS.SESSION, id, encode({ idle_timeout = timeout }), SESSION_TIMEOUT)
    shm_add(NS.STATE, id, STATE.LISTEN, SESSION_TIMEOUT)
    shm_await_state(id, STATE.CONNECT)

    log(DEBUG, "session upstream ACCEPT: ", id)
    shm_transition(id, STATE.ACCEPT, STATE.CONNECT)
    return shm_read(NS.HANDSHAKE, id, "get")
  end,

  connect = function(id, request)
    log(DEBUG, "session client SESSION: ", id)
    local data = shm_get(NS.SESSION, id)

    if not data then
      return exit(404, { error = fmt("session %s not found", id) })
    end

    local listen = decode(data)
    if not listen then
      return exit(500, { error = fmt("session %s data invalid: %s", id, data) })
    end

    log(DEBUG, "session client HANDSHAKE: ", id)
    shm_add(NS.HANDSHAKE, id, encode(request))

    log(DEBUG, "session client CONNECT: ", id)
    shm_transition(id, STATE.CONNECT, STATE.LISTEN)
    shm_await_state(id, STATE.ACCEPT)

    return listen
  end,

  abort = function(id)
    log(WARN, "session ABORT: ", id)
    shm_set(NS.STATE, id, STATE.ABORT)
  end,

  aborted = function(id)
    return shm_get(NS.STATE, id) == STATE.ABORT
  end,

  cleanup = function(role, id)
    shm:delete(make_key(role, id))
  end,

  write = function(role, id, data)
    shm_push(role, id, data)
  end,

  close = function(role, id)
    shm_push(role, id, EOF)
  end,
}


local function init_ws_server(ctx)
  local ws, err = ws_server:new({
    timeout         = 5000,
    max_payload_len = 2^31,
  })

  if not ws then
    log(ERR, "failed creating websocket server: ", err)
    return exit(444)
  end

  ctx.ws = ws
end


function _M.rewrite()
  local ctx = ngx.ctx
  ctx.request = request_infos()
  local id = ctx.request.headers[HEADERS.id] or utils.uuid()

  ctx.request_id = id
  header[HEADERS.id] = id

  -- for testing header forwarding
  header[HEADERS.self] = "1"
  header[HEADERS.multi] = { "one", "two" }

  -- masquerade as mock_upstream
  header["X-Powered-By"] = "mock_upstream"

  -- allow the client to specify some response headers for us to send
  for name, value in pairs(ctx.request.headers) do
    name = ngx.re.gsub(name, "^x-mock-websocket-echo-(.+)", "$1", "oji")
    if name then
      header[name] = value
    end
  end
end


function _M.echo()
  local ctx = ngx.ctx
  init_ws_server(ctx)

  log(INFO, "new echo server session")

  ---@type resty.websocket.server
  local ws = ctx.ws

  local data, typ, sent, err

  local closing = false

  on_abort(function()
    log(WARN, "handling client abort")
    closing = true
  end)

  while not closing and not exiting() do
    data, typ, err = ws:recv_frame()

    if data then
      if typ == "close" then
        closing = true
        sent, err = ws:send_close(err, data)

      elseif typ == "binary" or typ == "text" then
        if data == const.tokens.request then
          data = encode(ctx.request)

        elseif data == const.tokens.response then
          data = encode(response_infos())
        end

        sent, err = ws:send_frame(is_fin(err), OPCODES[typ], data)

      elseif typ == "ping" then
        sent, err = ws:send_pong(data)

      elseif typ == "pong" then
        log(INFO, "client ponged: ", data)

      else
        log(ERR, "unhandled echo frame type: ", typ)
        closing = true
      end

    elseif is_closed(err) or is_client_abort(err) then
      log(ERR, "client aborted connection, exiting")
      closing = true

    elseif not is_timeout(err) then
      log(ERR, "unexpected error while receiving frame: ", err)
      closing = true
    end

    if not sent and not closing then
      log(ERR, "failed sending echo frame: ", err)
      closing = true
    end
  end

  log(INFO, "echo server terminating...")
end

---
-- Reads from shm and forwards downstream
--
---@param role         string
---@param id           string
---@param sock         tcpsock
---@param idle_timeout integer?
local function shm_to_sock(role, id, sock, idle_timeout)
  local msg, sent, err

  local read_timeout = idle_timeout * 0.1
  local last = now()

  local peer = PEER[role]

  while not exiting() do
    msg, err = shm_read(role, id, "pop", read_timeout)

    if msg == EOF then
      log(INFO, role, " reached end of stream")
      break

    elseif msg then
      log(DEBUG, "sock(", role, ") <- shm, len: ", #msg)
      last = now()
      sent, err = sock:send(msg)

      if not sent then
        log(ERR, "failed forwarding from shm: ", err)
        break
      end

    elseif err == "timeout" then
      local idle = now() - last

      if idle > idle_timeout then
        log(NOTICE, "reader session timed out")
        break

      elseif session.aborted(id) then
        log(WARN, "peer (", peer, ") aborted connection")
        break
      end

    elseif err == "exiting" then
      break

    else
      log(ERR, "error while reading from shm: ", err or "unknown")
      break
    end
  end

  log(INFO, role, " shm_to_sock exiting")

  session.cleanup(role, id)

  return "reader"
end

---
-- Reads from a socket and writes to shm
--
---@param role    string
---@param id      string
---@param sock    tcpsock
---@param timeout integer?
local function sock_to_shm(role, id, sock, timeout)
  local last = now()

  local peer = PEER[role]

  while not exiting() do
    sock:settimeout(timeout * 1000)
    local data, err = sock:receiveany(1024 * 128)

    if data then
      last = now()

      log(DEBUG, "sock(", role, ") -> shm, len: ", #data)
      session.write(peer, id, data)

    elseif is_client_abort(err) then
      log(WARN, "sock_to_shm ", role, " abort")
      session.abort(id)
      break

    elseif is_timeout(err) then
      local idle = now() - last
      if idle > timeout then
        log(ERR, role, " reached idle timeout")
        break

      elseif session.aborted(id) then
        log(WARN, peer, " aborted connection")
        break
      end

    elseif is_closed(err) or is_reset(err) then
      break

    else
      log(ERR, "unexpected sock:receiveany() error: ", err)
      break
    end
  end

  log(INFO, role, " sock_to_shm exiting")

  session.close(peer, id)

  return "writer"
end

---@param role string
---@param sock tcpsock
---@param id string
local function pipe(role, sock, id, idle_timeout)
  local reader = spawn(shm_to_sock, role, id, sock, idle_timeout)
  local writer = spawn(sock_to_shm, role, id, sock, idle_timeout)

  local _, res = wait(reader, writer)

  local abort = session.aborted(id)

  local term = abort
               and kill
               or wait

  if res == "reader" then
    term(writer)

  elseif res == "writer" then
    term(reader)

  else
    log(ERR, "thread exited with error: ", res)
    kill(reader)
    kill(writer)
  end

  log(INFO, "closing ", role, " session...")

  if abort then
    exit(444)
  end
end


---
-- Upsream/Listener side of a WS session
function _M.listen()
  local t = var.arg_idle_timeout
  if t and not tonumber(t) then
    return exit(400, { error = "invalid idle_timeout: " .. t })
  end

  t = t and tonumber(t) and tonumber(t) / 1000
  t = t or IDLE_TIMEOUT

  local ctx = ngx.ctx
  init_ws_server(ctx)

  local id = ctx.request_id

  local data, err = session.accept(id, t)

  if err == "timeout" then
    log(ERR, "timed out waiting for client connection")
    return

  elseif not data then
    log(ERR, "error reading from shm while waiting for client: ", err)
    return
  end

  assert(ctx.ws:send_text(encode(data)))

  pipe(NS.UPSTREAM, ctx.ws.sock, id, t)
end


---
-- Client side of a WS session
function _M.client()
  local id = var.arg_session
  if not id or id == "" then
    return exit(400, { error = "session query arg is required" })
  end

  local ctx = ngx.ctx
  local listen = session.connect(id, ctx.request)

  init_ws_server(ctx)

  pipe(NS.CLIENT, ctx.ws.sock, id, listen.idle_timeout)
end


function _M.get_log()
  local id = var.log_id
  local timeout = tonumber(var.arg_timeout) or 1

  local entry = shm_read("log", id, "get", timeout)

  if not entry then
    return exit(404, {
      error = fmt("log for request %s not found", id),
    })
  end

  return exit(200, entry)
end


function _M.log_to_shm()
  local id = header[HEADERS.id] or ngx.req.get_headers()[HEADERS.id]

  if not id then
    log(ngx.WARN, "Request with no ", HEADERS.id, " request/response header")
    return
  end

  local entry = cjson.encode(kong.log.serialize())
  shm_set("log", id, entry)
end


return _M
