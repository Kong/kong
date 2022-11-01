local pb = require "pb"
local queue = require "kong.tools.wrpc.queue"
local threads = require "kong.tools.wrpc.threads"
local future = require "kong.tools.wrpc.future"

local pb_encode = pb.encode
local queue_new = queue.new
local future_new = future.new

local ngx_log = ngx.log
local NOTICE = ngx.NOTICE
local ngx_now = ngx.now
local DEFAULT_EXPIRATION_DELAY = 90

pb.option("no_default_values")

local _M = {}
local _MT = {}
_MT.__index = _M

_M.spawn_threads = threads.spawn
_M.wait_threads = threads.wait

local function is_wsclient(conn)
  return conn and not conn.close or nil
end

--- a `peer` object holds a (websocket) connection and a service.
--- @param conn table WebSocket connection to use.
--- @param service table Proto object that holds Serivces the connection supports.
function _M.new_peer(conn, service, timeout)
  return setmetatable({
    conn = conn,
    service = service,
    seq = 1,
    request_queue = is_wsclient(conn) and queue_new(),
    responses = {},
    closing = false,
    _receiving_thread = nil,
    timeout = timeout or DEFAULT_EXPIRATION_DELAY,
  }, _MT)
end

-- functions for managing connection

-- NOTICE: the caller is responsible to call this function before you can
-- not reach the peer.
--
-- A peer spwan threads refering itself, even if you cannot reach the object.
--
-- Therefore it's impossible for __gc to kill the threads
-- and close the WebSocket connection.
function _M:close()
  self.closing = true
  self.conn:send_close()
  if self.conn.close then
    self.conn:close()
  end
end


function _M:send(d)
  if self.request_queue then
    return self.request_queue:push(d)
  end

  return self.conn:send_binary(d)
end

function _M:receive()
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
--- @param rpc(table) name of RPC to call or response
--- @param payloads(string) payloads to send
--- @return kong.tools.wrpc.future|nil future, string|nil err
function _M:send_encoded_call(rpc, payloads)
  local response_future = future_new(self, self.timeout)
  local ok, err = self:send_payload({
    mtype = "MESSAGE_TYPE_RPC",
    svc_id = rpc.svc_id,
    rpc_id = rpc.rpc_id,
    payload_encoding = "ENCODING_PROTO3",
    payloads = payloads,
  })
  if not ok then return nil, err end
  return response_future
end

local send_encoded_call = _M.send_encoded_call

-- Make an RPC call.
--
-- Returns immediately.
-- Caller is responsible to call wait() for the returned future.
--- @param name(string) name of RPC to call, like "ConfigService.Sync"
--- @param arg(table) arguments of the call, like {config = config}
--- @return kong.tools.wrpc.future|nil future, string|nil err
function _M:call(name, arg)
  local rpc, payloads = assert(self.service:encode_args(name, arg))
  return send_encoded_call(self, rpc, payloads)
end


-- Make an RPC call.
--
-- Block until the call is responded or an error occurs.
--- @async
--- @param name(string) name of RPC to call, like "ConfigService.Sync"
--- @param arg(table) arguments of the call, like {config = config}
--- @return any data, string|nil err result of the call
function _M:call_async(name, arg)
  local future_to_wait, err = self:call(name, arg)

  return future_to_wait and future_to_wait:wait(), err
end

-- Make an RPC call.
--
-- Returns immediately and ignore response of the call.
--- @param name(string) name of RPC to call, like "ConfigService.Sync"
--- @param arg(table) arguments of the call, like {config = config}
--- @return boolean|nil ok, string|nil err result of the call
function _M:call_no_return(name, arg)
  local future_to_wait, err = self:call(name, arg)
  if not future_to_wait then return nil, err end
  return future_to_wait:drop()
end


--- encodes and sends a wRPC message.
--- Assumes protocol fields are already filled (except `.seq` and `.deadline`)
--- and payload data (if any) is already encoded with the right type.
--- Keeps track of the sequence number and assigns deadline.
function _M:send_payload(payload)
  local seq = self.seq
  payload.seq = seq
  self.seq = seq + 1

  -- protobuf may confuse with 0 value and nil(undefined) under some set up
  -- so we will just handle 0 as nil
  if not payload.ack or payload.ack == 0 then
    payload.deadline = ngx_now() + self.timeout
  end

  return self:send(pb_encode("wrpc.WebsocketPayload", {
    version = "PAYLOAD_VERSION_V1",
    payload = payload,
  }))
end

return _M
