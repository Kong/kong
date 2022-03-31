local pb = require "pb"
local grpc = require "kong.tools.grpc"
local semaphore = require "ngx.semaphore"
require "table.new"

local select = select
local table_unpack = table.unpack     -- luacheck: ignore
local table_insert = table.insert
local table_remove = table.remove

local exiting = ngx.worker.exiting

local DEFAULT_EXPIRATION_DELAY = 90

local wrpc = {}


local Queue = {}
Queue.__index = Queue

function Queue.new()
  return setmetatable({
    smph = semaphore.new(),
  }, Queue)
end

function Queue:push(itm)
  table_insert(self, itm)
  return self.smph:post()
end

function Queue:pop(timeout)
  local ok, err = self.smph:wait(timeout or 1)
  if not ok then
    return nil, err
  end

  return table_remove(self, 1)
end

local semaphore_waiter
do
  local function trigger(self, data)
    self.data = data
    self.smph:post()
  end

  local function expire(self)
    self.data = nil
    self.error = "timeout"
    self.smph:post()
  end

  function semaphore_waiter()
    return {
      smph = semaphore.new(),
      deadline = ngx.now() + DEFAULT_EXPIRATION_DELAY,
      handle = trigger,
      expire = expire,
    }
  end
end


local function merge(a, b)
  if type(b) == "table" then
    for k, v in pairs(b) do
      a[k] = v
    end
  end

  return a
end

local function proto_searchpath(name)
  return package.searchpath(name, "/usr/include/?.proto;../koko/internal/wrpc/proto/?.proto;../go-wrpc/wrpc/internal/wrpc/?.proto")
end

--- definitions for the transport protocol
local wrpc_proto


local wrpc_service = {}
wrpc_service.__index = wrpc_service


--- a `service` object holds a set of methods defined
--- in .proto files
function wrpc.new_service()
  if not wrpc_proto then
    local wrpc_protofname = assert(proto_searchpath("wrpc"))
    wrpc_proto = assert(grpc.each_method(wrpc_protofname))
    --pp("wrpc_proto", wrpc_proto)
  end

  return setmetatable({
    methods = {},
  }, wrpc_service)
end

--- Loads the methods from a .proto file.
--- There can be more than one file, and any number of
--- service definitions.
function wrpc_service:add(service_name)
  local annotations = {
    service = {},
    rpc = {},
  }
  local service_fname = assert(proto_searchpath(service_name))
  local proto_f = assert(io.open(service_fname))
  local scope_name = ""

  for line in proto_f:lines() do
    local annotation = line:match("//%s*%+wrpc:%s*(.-)%s*$")
    if annotation then
      local nextline = proto_f:read("*l")
      local keyword, identifier = nextline:match("^%s*(%a+)%s+(%w+)")
      if keyword and identifier then

        if keyword == "service" then
          scope_name = identifier;

        elseif keyword == "rpc" then
          identifier = scope_name .. "." .. identifier
        end

        local type_annotations = annotations[keyword]
        if type_annotations then
          local tag_key, tag_value = annotation:match("^%s*(%S-)=(%S+)%s*$")
          if tag_key and tag_value then
            tag_value = tag_value
            local tags = type_annotations[identifier] or {}
            type_annotations[identifier] = tags
            tags[tag_key] = tag_value
          end
        end
      end
    end
  end
  proto_f:close()

  grpc.each_method(service_fname, function(_, srvc, mthd)
    assert(srvc.name)
    assert(mthd.name)
    local rpc_name = srvc.name .. "." .. mthd.name

    local service_id = assert(annotations.service[srvc.name] and annotations.service[srvc.name]["service-id"])
    local rpc_id = assert(annotations.rpc[rpc_name] and annotations.rpc[rpc_name]["rpc-id"])
    local rpc = {
      name = rpc_name,
      service_id = tonumber(service_id),
      rpc_id = tonumber(rpc_id),
      input_type = mthd.input_type,
      output_type = mthd.output_type,
    }
    self.methods[service_id .. ":" .. rpc_id] = rpc
    self.methods[rpc_name] = rpc
  end, true)
end

--- returns the method defintion given either:
--- pair of IDs (service, rpc) or
--- rpc name as "<service_name>.<rpc_name>"
function wrpc_service:get_method(srvc_id, rpc_id)
  local rpc_name
  if type(srvc_id) == "string" and rpc_id == nil then
    rpc_name = srvc_id
  else
    rpc_name = tostring(srvc_id) .. ":" .. tostring(rpc_id)
  end

  return self.methods[rpc_name]
end

--- sets a service handler for the givern rpc method
--- @param rpc_name string Full name of the rpc method
--- @param handler function Function called to handle the rpc method.
--- @param response_handler function Fallback function called to handle responses.
function wrpc_service:set_handler(rpc_name, handler, response_handler)
  local rpc = self:get_method(rpc_name)
  if not rpc then
    return nil, string.format("unknown method %q", rpc_name)
  end

  rpc.handler = handler
  rpc.response_handler = response_handler
  return rpc
end


--- Part of wrpc_peer:call()
--- If calling the same method with the same args several times,
--- (to the same or different peers), this method returns the
--- invariant part, so it can be cached to reduce encoding overhead
function wrpc_service:encode_args(name, ...)
  local rpc = self:get_method(name)
  if not rpc then
    return nil, string.format("no method %q", name)
  end

  local num_args = select('#', ...)
  local payloads = table.new(num_args, 0)
  for i = 1, num_args do
    payloads[i] = assert(pb.encode(rpc.input_type, select(i, ...)))
  end

  return rpc, payloads
end


local wrpc_peer = {
  encode = pb.encode,
  decode = pb.decode,
}
wrpc_peer.__index = wrpc_peer

--- a `peer` object holds a (websocket) connection and a service.
function wrpc.new_peer(conn, service, opts)
  return setmetatable(merge({
    conn = conn,
    service = service,
    seq = 1,
    request_queue = (not conn.close) and Queue.new(),
    response_queue = {},
    closing = false,
    _receiving_thread = nil,
  }, opts), wrpc_peer)
end


function wrpc_peer:close()
  self.closing = true
  self.conn:send_close()
  if self.conn.close then
    self.conn:close()
  end
end


function wrpc_peer:send(d)
  if self.request_queue then
    return self.request_queue:push(d)
  end

  return self.conn:send_binary(d)
end

function wrpc_peer:receive()
  while true do
    local data, typ, err = self.conn:recv_frame()
    if not data then
      return nil, err
    end

    if typ == "binary" then
      return data
    end

    if typ == "close" then
      kong.log.notice("Received WebSocket \"close\" frame from peer")
      return self:close()
    end
  end
end

--- RPC call.
--- returns the call sequence number, doesn't wait for response.
function wrpc_peer:call(name, ...)
  local rpc, payloads = assert(self.service:encode_args(name, ...))
  return self:send_encoded_call(rpc, payloads)
end


function wrpc_peer:call_wait(name, ...)
  local waiter = semaphore_waiter()

  local seq = self.seq
  self.response_queue[seq] = waiter
  local new_seq = self:call(name, ...)
  assert(new_seq == seq)

  waiter.smph:wait()
  return waiter.data
end


--- Part of wrpc_peer:call()
--- This performs the per-call parts.  The arguments
--- are the return values from wrpc_peer:encode_args(),
--- either directly or cached (to repeat the same call
--- several times).
function wrpc_peer:send_encoded_call(rpc, payloads)
  self:send_payload({
    mtype = "MESSAGE_TYPE_RPC",
    svc_id = rpc.service_id,
    rpc_id = rpc.rpc_id,
    payload_encoding = "ENCODING_PROTO3",
    payloads = payloads,
  })
  return self.seq
end

--- little helper to ease grabbing an unspecified number of
local function ok_wrapper(ok, ...)
  return ok, {n = select('#', ...), ...}
end

local function decodearray(decode, typ, l)
  local out = {}
  for i, v in ipairs(l) do
    out[i] = decode(typ, v)
  end
  return out
end

local function encodearray(encode, typ, l)
  local out = {}
  for i = 1, l.n do
    out[i] = encode(typ, l[i])
  end
  return out
end


function wrpc_peer:send_payload(payload)
  local seq = self.seq
  payload.seq = seq
  self.seq = seq + 1

  payload.deadline = ngx.now() + DEFAULT_EXPIRATION_DELAY

  self:send(self.encode("wrpc.WebsocketPayload",{
    version = "PAYLOAD_VERSION_V1",
    payload = payload,
  }))
end


--- Handle RPC data (mtype == MESSAGE_TYPE_RPC).
--- Could be an incoming method call or the response to a previous one.
--- @param payload table decoded payload field from incoming `wrpc.WebsocketPayload` message
function wrpc_peer:handle(payload)
  local rpc = self.service:get_method(payload.svc_id, payload.rpc_id)
  if not rpc then
    self:send_payload({
      mtype = "MESSAGE_TYPE_ERROR",
      error = {
        etype = "ERROR_TYPE_INVALID_SERVICE",
        description = "Invalid service (or rpc)",
      },
      srvc_id = payload.svc_id,
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

      if response_waiter.deadline and response_waiter.deadline < ngx.now() then
        if response_waiter.expire then
          response_waiter:expire()
        end

      else
        response_waiter:handle(decodearray(self.decode, rpc.output_type, payload.payloads))
      end
      self.response_queue[ack] = nil

    elseif rpc.response_handler then
      pcall(rpc.response_handler, self, decodearray(self.decode, rpc.output_type, payload.payloads))
    end

  else
    -- incoming method call
    if rpc.handler then
      local input_data = decodearray(self.decode, rpc.input_type, payload.payloads)
      local ok, output_data = ok_wrapper(pcall(rpc.handler, self, table_unpack(input_data, 1, input_data.n)))
      if not ok then
        self:send_payload({
          mtype = "MESSAGE_TYPE_ERROR",
          error = {
            etype = "ERROR_TYPE_UNSPECIFIED",
            description = tostring(output_data),
          },
          srvc_id = payload.svc_id,
          rpc_id = payload.rpc_id,
          ack = payload.seq,
        })
        return nil, output_data
      end

      self:send_payload({
        mtype = "MESSAGE_TYPE_RPC", -- MESSAGE_TYPE_RPC,
        svc_id = rpc.service_id,
        rpc_id = rpc.rpc_id,
        ack = payload.seq,
        payload_encoding = "ENCODING_PROTO3",
        payloads = encodearray(self.encode, rpc.output_type, output_data),
      })
    end
  end
end


--- Handle incoming error message (mtype == MESSAGE_TYPE_ERROR).
function wrpc_peer:handle_error(payload)
  local etype = payload.error and payload.error.etype or "--"
  local errdesc = payload.error and payload.error.description or "--"
  ngx.log(ngx.NOTICE, string.format("[wRPC] Received error message, %s.%s:%s (%s: %q)",
    payload.svc_id, payload.rpc_id, payload.ack, etype, errdesc
  ))

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_waiter = self.response_queue[ack]
    if response_waiter and response_waiter.handle_error then

      if response_waiter.deadline and response_waiter.deadline < ngx.now() then
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


function wrpc_peer:step()
  local msg = self:receive()

  while msg ~= nil do
    msg = assert(self.decode("wrpc.WebsocketPayload", msg))
    assert(msg.version == "PAYLOAD_VERSION_V1", "unknown encoding version")
    local payload = msg.payload

    if payload.mtype == "MESSAGE_TYPE_ERROR" then
      self:handle_error(payload)

    elseif payload.mtype == "MESSAGE_TYPE_RPC" then
      if payload.deadline >= ngx.now() then
        self:handle(payload)
      else
        ngx.log(ngx.NOTICE, "[wRPC] Expired message (", payload.deadline, "<", ngx.now(), ") discarded")
      end
    end

    msg = self:receive()
  end
end

function wrpc_peer:spawn_threads()
  self._receiving_thread = assert(ngx.thread.spawn(function()
    while not exiting() and not self.closing do
      self:step()
      ngx.sleep(0)
    end
  end))

  if self.request_queue then
    self._transmit_thread = assert(ngx.thread.spawn(function()
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
end


function wrpc_peer:wait_threads()
  local ok, err, perr = ngx.thread.wait(self._receiving_thread, self._transmit_thread)

  if self._receiving_thread then
    ngx.thread.kill(self._receiving_thread)
    self._receiving_thread = nil
  end

  if self._transmit_thread then
    ngx.thread.kill(self._transmit_thread)
    self._transmit_thread = nil
  end

  return ok, err, perr
end

--- Returns the response for a given call ID, if any
function wrpc_peer:get_response(req_id)
  local resp_data = self.response_queue[req_id]
  self.response_queue[req_id] = nil

  if resp_data == nil then
    return nil, "no response"
  end

  return resp_data
end


return wrpc
