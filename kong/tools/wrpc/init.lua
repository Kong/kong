local pb = require "pb"
local semaphore = require "ngx.semaphore"
local util = require "kong.tools.wrpc.util"
local threads = require "kong.tools.wrpc.threads"

local pb_encode = pb.encode
local queue = util.queue
local queue_new = queue.new

local ngx_log = ngx.log
local NOTICE = ngx.NOTICE
local ngx_now = ngx.now
local DEFAULT_EXPIRATION_DELAY = 90

pb.option("no_default_values")

local _M = {}

_M.spawn_threads = threads.spawn
_M.wait_threads = threads.wait

local semaphore_waiter
do
  local function handle(self, data)
    self.data = data
    self.smph:post()
  end

  local function handle_error(self, etype, errdesc)
    self.data = nil
    self.error = errdesc
    self.etype = etype
    self.smph:post()
  end

  local function expire(self)
    self:handle_error("timeout", "timeout")
  end

  function semaphore_waiter()
    return {
      smph = semaphore.new(),
      deadline = ngx_now() + DEFAULT_EXPIRATION_DELAY,
      handle = handle,
      handle_error = handle_error,
      expire = expire,
    }
  end
end

local _MT = {}

local function is_wsclient(conn)
  return conn and not conn.close or nil
end

--- a `peer` object holds a (websocket) connection and a service.
--- @param conn table WebSocket connection to use.
--- @param service table Proto object that holds Serivces the connection supports.
function _M.new_peer(conn, service)
  return setmetatable({
    conn = conn,
    service = service,
    seq = 1,
    request_queue = is_wsclient(conn) and queue_new(),
    response_queue = {},
    closing = false,
    _receiving_thread = nil,
  }, _MT)
end

-- functions for managing connection

function _MT:close()
  self.closing = true
  self.conn:send_close()
  if self.conn.close then
    self.conn:close()
  end
end


function _MT:send(d)
  if self.request_queue then
    return self.request_queue:push(d)
  end

  return self.conn:send_binary(d)
end

function _MT:receive()
  while true do
    local data, typ, err = self.conn:recv_frame()
    if not data then
      return nil, err
    end

    if typ == "binary" then
      return data
    end

    if typ == "close" then
      ngx_log(NOTICE, "Received WebSocket \"close\" frame from peer: ", err, ": ", data)
      return self:close()
    end
  end
end

-- functions to send call

--- Part of wrpc_peer:call()
--- This performs the per-call parts.  The arguments
--- are the return values from wrpc_peer:encode_args(),
--- either directly or cached (to repeat the same call
--- several times).
function _MT:send_encoded_call(rpc, payloads)
  self:send_payload({
    mtype = "MESSAGE_TYPE_RPC",
    svc_id = rpc.svc_id,
    rpc_id = rpc.rpc_id,
    payload_encoding = "ENCODING_PROTO3",
    payloads = payloads,
  })
  return self.seq
end

local send_encoded_call = _MT.send_encoded_call

--- RPC call.
--- returns the call sequence number, doesn't wait for response.
function _MT:call(name, ...)
  local rpc, payloads = assert(self.service:encode_args(name, ...))
  return send_encoded_call(self, rpc, payloads)
end


function _MT:call_wait(name, ...)
  local waiter = semaphore_waiter()

  local seq = self.seq
  self.response_queue[seq] = waiter
  self:call(name, ...)

  local ok, err = waiter.smph:wait(DEFAULT_EXPIRATION_DELAY)
  if not ok then
    return nil, err
  end
  return waiter.data, waiter.error
end


--- encodes and sends a wRPC message.
--- Assumes protocol fields are already filled (except `.seq` and `.deadline`)
--- and payload data (if any) is already encoded with the right type.
--- Keeps track of the sequence number and assigns deadline.
function _MT:send_payload(payload)
  local seq = self.seq
  payload.seq = seq
  self.seq = seq + 1

  if not payload.ack or payload.ack == 0 then
    payload.deadline = ngx_now() + DEFAULT_EXPIRATION_DELAY
  end

  self:send(pb_encode("wrpc.WebsocketPayload", {
    version = "PAYLOAD_VERSION_V1",
    payload = payload,
  }))
end


--- Returns the response for a given call ID, if any
function _MT:get_response(req_id)
  local resp_data = self.response_queue[req_id]
  self.response_queue[req_id] = nil

  if resp_data == nil then
    return nil, "no response"
  end

  return resp_data
end

return _M
