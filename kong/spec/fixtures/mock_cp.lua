local _M = {}

local ws_server = require "resty.websocket.server"
local pl_file = require "pl.file"
local cjson = require "cjson.safe"
local semaphore = require "ngx.semaphore"
local gzip = require "kong.tools.gzip"
local buffer = require "string.buffer"

local shm = assert(ngx.shared.kong_test_cp_mock)

local WRITER = "writer"
local READER = "reader"

---@type resty.websocket.new.opts
local WS_OPTS = {
  timeout = 500,
  max_payload_len = 1024 * 1024 * 20,
}


---@class spec.fixtures.cluster-mock.ctx
---
---@field basic_info   table
---@field cancel       boolean
---@field dp           table
---@field need_pong    boolean
---@field writer_sema  ngx.semaphore
---@field ws           resty.websocket.server
---@field sent_version integer


local function send(status, json)
  ngx.status = status
  ngx.print(cjson.encode(json))
  return ngx.exit(status)
end


local function bad_request(err)
  send(ngx.HTTP_BAD_REQUEST, { error = err })
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@param entry table
local function emit_log_entry(ctx, entry)
  entry.dp = ctx.dp
  assert(shm:rpush("log", buffer.encode(entry)))
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@param name string
---@param data table?
local function log_event(ctx, name, data)
  local evt = data or {}
  evt.event = name
  emit_log_entry(ctx, evt)
end


---@return integer
local function get_version()
  return shm:get("payload-version") or 0
end


---@return integer
local function increment_version()
  return assert(shm:incr("payload-version", 1, 0))
end


---@param ctx spec.fixtures.cluster-mock.ctx
local function wake_writer(ctx)
  ctx.writer_sema:post(1)
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@return boolean
local function canceled(ctx)
  return ctx.cancel or ngx.worker.exiting()
end


---@param ctx spec.fixtures.cluster-mock.ctx
local function wait_writer(ctx)
  return canceled(ctx) or ctx.writer_sema:wait(0.1)
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@return boolean continue
local function get_basic_info(ctx)
  local data, typ, err = ctx.ws:recv_frame()

  if err and err:find("timeout") then
    return true

  elseif not data then
    log_event(ctx, "client-read-error", { error = err })
    return false
  end

  if typ == "binary" then
    local info = cjson.decode(data)

    if type(info) == "table" and info.type == "basic_info" then
      log_event(ctx, "client-basic-info-received")
      wake_writer(ctx)
      ctx.basic_info = info
      return true

    else
      log_event(ctx, "client-error",
      { error = "client did not send proper basic info frame" })

      return false
    end

  else
    log_event(ctx, "client-error", {
      error = "invalid pre-basic-info frame type: " .. typ,
    })
    return false
  end
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@return boolean continue
local function reader_recv(ctx)
  local data, typ, err = ctx.ws:recv_frame()

  if err then
    if err:find("timeout") then
      return true
    end

    log_event(ctx, "client-read-error", { error = err })
    return false
  end

  log_event(ctx, "client-recv", {
    type = typ,
    data = data,
    json = cjson.decode(data),
  })

  if typ == "ping" then
    ctx.need_pong = true
    wake_writer(ctx)

  elseif typ == "close" then
    log_event(ctx, "close", { initiator = "dp" })
    return false
  end

  return true
end


---@param ctx spec.fixtures.cluster-mock.ctx
local function read_handler(ctx)
  while not canceled(ctx) and not ctx.basic_info do
    if not get_basic_info(ctx) then
      return READER
    end
  end

  while not canceled(ctx) do
    if not reader_recv(ctx) then
      break
    end
  end

  return READER
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@return boolean continue
local function handle_ping(ctx)
  if ctx.need_pong then
    ctx.need_pong = false
    ctx.ws:send_pong()
  end

  return true
end


---@param ctx spec.fixtures.cluster-mock.ctx
---@return boolean continue
local function send_config(ctx)
  local version = get_version()

  if version <= ctx.sent_version then
    return true
  end

  local data = assert(shm:get("payload"))
  local payload = gzip.deflate_gzip(data)

  local ok, err = ctx.ws:send_binary(payload)

  if ok then
    log_event(ctx, "sent-config", {
      version       = version,
      size          = #data,
      deflated_size = #payload,
    })
    ctx.sent_version = version
    return true

  else
    log_event(ctx, "send-error", { error = err })
    return false
  end
end


---@param ctx spec.fixtures.cluster-mock.ctx
local function write_handler(ctx)
  while not ctx.basic_info and not canceled(ctx) do
    wait_writer(ctx)
  end

  -- wait until the test driver has sent us at least one config payload
  while get_version() < 1 and not canceled(ctx) do
    wait_writer(ctx)
  end

  ctx.sent_version = 0

  while not canceled(ctx)
    and handle_ping(ctx)
    and send_config(ctx)
  do
    wait_writer(ctx)
  end

  return WRITER
end


function _M.outlet()
  local dp = {
    id       = ngx.var.arg_node_id,
    hostname = ngx.var.arg_node_hostname,
    ip       = ngx.var.remote_addr,
    version  = ngx.var.arg_node_version,
  }

  local ctx = ngx.ctx
  ctx.dp = dp

  log_event(ctx, "connect")

  local ws, err = ws_server:new(WS_OPTS)

  if ws then
    log_event(ctx, "handshake", { ok = true, err = nil })
  else
    log_event(ctx, "handshake", { ok = false, err = err })
    log_event(ctx, "close", { initiator = "cp" })
    return ngx.exit(ngx.HTTP_CLOSE)
  end

  ws:set_timeout(500)

  ctx.ws = ws
  ctx.cancel = false
  ctx.writer_sema = semaphore.new()

  local reader = ngx.thread.spawn(read_handler, ctx)
  local writer = ngx.thread.spawn(write_handler, ctx)

  local ok, err_or_result = ngx.thread.wait(reader, writer)

  ctx.cancel = true
  wake_writer(ctx)

  ws:send_close()

  if ok then
    local res = err_or_result
    local thread
    if res == READER then
      thread = writer

    elseif res == WRITER then
      thread = reader

    else
      error("unreachable!")
    end

    ngx.thread.wait(thread)
    ngx.thread.kill(thread)

  else
    ngx.log(ngx.ERR, "abnormal ngx.thread.wait() status: ", err_or_result)
    ngx.thread.kill(reader)
    ngx.thread.kill(writer)
  end

  log_event(ctx, "exit")
end


function _M.set_payload()
  ngx.req.read_body()

  local body = ngx.req.get_body_data()
  if not body then
    local body_file = ngx.req.get_body_file()
    if body_file then
      body = pl_file.read(body_file)
    end
  end

  if not body then
    return bad_request("expected request body")
  end

  local json, err = cjson.decode(body)
  if err then
    return bad_request("invalid JSON: " .. tostring(err))
  end

  assert(shm:set("payload", cjson.encode(json)))
  local version = increment_version()

  return send(201, {
    status = "created",
    message = "updated payload",
    version = version,
  })
end

function _M.get_log()
  local entries = {}

  repeat
    local data = shm:lpop("log")
    if data then
      table.insert(entries, buffer.decode(data))
    end
  until not data

  send(200, { data = entries })
end


function _M.fixture(listen, listen_ssl)
  return ([[
lua_shared_dict kong_test_cp_mock 10m;

server {
    charset UTF-8;
    server_name kong_cluster_listener;
    listen %s;
    listen %s ssl;

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log  ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

> if cluster_mtls == "shared" then
    ssl_verify_client   optional_no_ca;
> else
    ssl_verify_client   on;
    ssl_client_certificate ${{CLUSTER_CA_CERT}};
    ssl_verify_depth     4;
> end
    ssl_certificate     ${{CLUSTER_CERT}};
    ssl_certificate_key ${{CLUSTER_CERT_KEY}};
    ssl_session_cache   shared:ClusterSSL:10m;

    location = /v1/outlet {
        content_by_lua_block {
            require("spec.fixtures.mock_cp").outlet()
        }
    }

    location = /payload {
        content_by_lua_block {
            require("spec.fixtures.mock_cp").set_payload()
        }
    }

    location = /log {
        content_by_lua_block {
            require("spec.fixtures.mock_cp").get_log()
        }
    }
}
]]):format(listen, listen_ssl)
end


return _M
