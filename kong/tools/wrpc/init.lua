local pb = require "pb"
local semaphore = require "ngx.semaphore"
local channel = require "kong.tools.channel"
local util = require "kong.tools.wrpc.util"

local table_unpack = table.unpack     -- luacheck: ignore
local pb_encode = pb.encode
local pb_decode = pb.decode
local ok_wrapper = util.ok_wrapper
local safe_args = util.safe_args
local endswith = util.endswith
local queue = util.queue
local queue_new = queue.new
local ngx_log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local exiting = ngx.worker.exiting
local ngx_now = ngx.now
local sleep = ngx.sleep
local thread_spawn = ngx.thread.spawn
local thread_kill = ngx.thread.kill
local thread_wait = ngx.thread.wait
local DEFAULT_EXPIRATION_DELAY = 90

pb.option("no_default_values")

local _M = {}

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

--- decodes each element of an array with the same type
local function decodearray(decode, typ, l)
  local out = {}
  for i, v in ipairs(l) do
    out[i] = decode(typ, v)
  end
  return out
end

--- encodes each element of an array with the same type
local function encodearray(encode, typ, l)
  local out = {}
  for i = 1, l.n do
    out[i] = encode(typ, l[i])
  end
  return out
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

--- Handle RPC data (mtype == MESSAGE_TYPE_RPC).
--- Could be an incoming method call or the response to a previous one.
--- @param payload table decoded payload field from incoming `wrpc.WebsocketPayload` message
function _MT:handle(payload)
  local rpc = self.service:get_rpc(payload.svc_id .. '.' .. payload.rpc_id)
  if not rpc then
    self:send_payload({
      mtype = "MESSAGE_TYPE_ERROR",
      error = {
        etype = "ERROR_TYPE_INVALID_SERVICE",
        description = "Invalid service (or rpc)",
      },
      svc_id = payload.svc_id,
      rpc_id = payload.rpc_id,
      ack = payload.seq,
    })
    return nil, "INVALID_SERVICE"
  end

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_waiter = self.response_queue[ack]
    if response_waiter then

      if response_waiter.deadline and response_waiter.deadline < ngx_now() then
        if response_waiter.expire then
          response_waiter:expire()
        end

      else
        if response_waiter.raw then
          response_waiter:handle(payload)
        else
          response_waiter:handle(decodearray(pb_decode, rpc.output_type, payload.payloads))
        end
      end
      self.response_queue[ack] = nil

    elseif rpc.response_handler then
      pcall(rpc.response_handler, self, decodearray(pb_decode, rpc.output_type, payload.payloads))
    end

  else
    -- incoming method call
    if rpc.handler then
      local input_data = decodearray(pb_decode, rpc.input_type, payload.payloads)
      local ok, output_data = ok_wrapper(pcall(rpc.handler, self, table_unpack(input_data, 1, input_data.n)))
      if not ok then
        local err = tostring(output_data[1])
        ngx_log(ERR, ("[wrpc] Error handling %q method: %q"):format(rpc.name, err))
        self:send_payload({
          mtype = "MESSAGE_TYPE_ERROR",
          error = {
            etype = "ERROR_TYPE_UNSPECIFIED",
            description = err,
          },
          svc_id = payload.svc_id,
          rpc_id = payload.rpc_id,
          ack = payload.seq,
        })
        return nil, err
      end

      self:send_payload({
        mtype = "MESSAGE_TYPE_RPC", -- MESSAGE_TYPE_RPC,
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id,
        ack = payload.seq,
        payload_encoding = "ENCODING_PROTO3",
        payloads = encodearray(pb_encode, rpc.output_type, output_data),
      })

    else
      -- rpc has no handler
      self:send_payload({
        mtype = "MESSAGE_TYPE_ERROR",
        error = {
          etype = "ERROR_TYPE_INVALID_RPC",   -- invalid here, not in the definition
          description = "Unhandled method",
        },
        svc_id = payload.svc_id,
        rpc_id = payload.rpc_id,
        ack = payload.seq,
      })
    end
  end
end


--- Handle incoming error message (mtype == MESSAGE_TYPE_ERROR).
function _MT:handle_error(payload)
  local etype = payload.error and payload.error.etype or "--"
  local errdesc = payload.error and payload.error.description or "--"
  ngx_log(NOTICE, string.format("[wRPC] Received error message, %s.%s:%s (%s: %q)",
    payload.svc_id, payload.rpc_id, payload.ack, etype, errdesc
  ))

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_waiter = self.response_queue[ack]
    if response_waiter and response_waiter.handle_error then

      if response_waiter.deadline and response_waiter.deadline < ngx_now() then
        if response_waiter.expire then
          response_waiter:expire()
        end

      else
        response_waiter:handle_error(etype, errdesc)
      end
      self.response_queue[ack] = nil

    else
      local rpc = self.service:get_method(payload.svc_id, payload.rpc_id)
      if rpc and rpc.error_handler then
        pcall(rpc.error_handler, self, etype, errdesc)
      end
    end
  end
end


function _MT:step()
  local msg, err = self:receive()

  while msg ~= nil do
    msg = assert(pb_decode("wrpc.WebsocketPayload", msg))
    assert(msg.version == "PAYLOAD_VERSION_V1", "unknown encoding version")
    local payload = msg.payload

    if payload.mtype == "MESSAGE_TYPE_ERROR" then
      self:handle_error(payload)

    elseif payload.mtype == "MESSAGE_TYPE_RPC" then
      local ack = payload.ack or 0
      local deadline = payload.deadline or 0

      if ack == 0 and deadline < ngx_now() then
        ngx_log(NOTICE, "[wRPC] Expired message (", deadline, "<", ngx_now(), ") discarded")

      elseif ack ~= 0 and deadline ~= 0 then
        ngx_log(NOTICE, "[WRPC] Invalid deadline (", deadline, ") for response")

      else
        self:handle(payload)
      end
    end

    msg, err = self:receive()
  end

  if err ~= nil and not endswith(err, "timeout") then
    ngx_log(NOTICE, "[wRPC] WebSocket frame: ", err)
    self.closing = true
  end
end

function _MT:spawn_threads()
  self._receiving_thread = assert(thread_spawn(function()
    while not exiting() and not self.closing do
      self:step()
      sleep(0)
    end
  end))

  if self.request_queue then
    self._transmit_thread = assert(thread_spawn(function()
      while not exiting() and not self.closing do
        local data, err = self.request_queue:pop()
        if data then
          self.conn:send_binary(data)

        else
          if err ~= "timeout" then
            return nil, err
          end
        end
      end
    end))
  end

  if self.channel_dict then
    self._channel_thread = assert(thread_spawn(function()
      while not exiting() and not self.closing do
        local msg, name, err = channel.wait_all(self.channel_dict)
        if msg and name then
          self:send_remote_payload(msg, name)

        else
          if err ~= "timeout" then
            return nil, err
          end
        end
      end
    end))
  end
end


function _MT:wait_threads()
  local ok, err, perr = thread_wait(safe_args(self._receiving_thread, self._transmit_thread, self._channel_thread))

  if self._receiving_thread then
    thread_kill(self._receiving_thread)
    self._receiving_thread = nil
  end

  if self._transmit_thread then
    thread_kill(self._transmit_thread)
    self._transmit_thread = nil
  end

  if self._channel_thread then
    thread_kill(self._channel_thread)
    self._channel_thread = nil
  end

  return ok, err, perr
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
