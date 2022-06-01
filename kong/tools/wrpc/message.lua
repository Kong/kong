
local pb = require "pb"

local tonumber = tonumber
local table_unpack = table.unpack -- luacheck: ignore
local select = select

local pb_decode = pb.decode
local pb_encode = pb.encode

local ngx_log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local ngx_now = ngx.now

-- utility functions

--- little helper to ease grabbing an unspecified number
--- of values after an `ok` flag
local function ok_wrapper(ok, ...)
  return ok, {n = select('#', ...), ...}
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


local _M = {}

local function send_error(wrpc_peer, payload, error)
  return wrpc_peer:send_payload({
    mtype = "MESSAGE_TYPE_ERROR",
    error = error,
    svc_id = payload.svc_id,
    rpc_id = payload.rpc_id,
    ack = payload.seq,
  })
end

--- Handle RPC data (mtype == MESSAGE_TYPE_RPC).
--- Could be an incoming method call or the response to a previous one.
--- @param payload table decoded payload field from incoming `wrpc.WebsocketPayload`
function _M.process_message(wrpc_peer, payload)
  local rpc = wrpc_peer.service:get_rpc(
    payload.svc_id .. '.' .. payload.rpc_id)
  if not rpc then
    send_error(wrpc_peer, {
      etype = "ERROR_TYPE_INVALID_SERVICE",
      description = "Invalid service (or rpc)",
    })
    return nil, "INVALID_SERVICE"
  end

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_future = wrpc_peer.responses[ack]
    if response_future then

      if response_future.deadline and response_future.deadline < ngx_now() then
        if response_future.expire then
          response_future:expire()
        end

      else
        if response_future.raw then
          response_future:done(payload)
        else
          response_future:done(
            decodearray(pb_decode, rpc.output_type, payload.payloads))
        end
      end

    elseif rpc.response_handler then
      pcall(rpc.response_handler,
        wrpc_peer, decodearray(pb_decode, rpc.output_type, payload.payloads))
    end

  else
    -- incoming method call
    if rpc.handler then
      local input_data = decodearray(pb_decode, rpc.input_type, payload.payloads)
      local ok, output_data = ok_wrapper(
        pcall(rpc.handler, wrpc_peer, table_unpack(input_data, 1, input_data.n)))
      if not ok then
        local err = tostring(output_data[1])
        ngx_log(ERR, ("[wrpc] Error handling %q method: %q"):format(rpc.name, err))

        send_error(wrpc_peer, {
          etype = "ERROR_TYPE_UNSPECIFIED",
          description = err,
        })

        return nil, err
      end

      wrpc_peer:send_payload({
        mtype = "MESSAGE_TYPE_RPC", -- MESSAGE_TYPE_RPC,
        svc_id = rpc.svc_id,
        rpc_id = rpc.rpc_id,
        ack = payload.seq,
        payload_encoding = "ENCODING_PROTO3",
        payloads = encodearray(pb_encode, rpc.output_type, output_data),
      })

    else
      -- rpc has no handler
      send_error(wrpc_peer, {
        etype = "ERROR_TYPE_INVALID_RPC",   -- invalid here, not in the definition
        description = "Unhandled method",
      })
    end
  end
end

--- Handle incoming error message (mtype == MESSAGE_TYPE_ERROR).
function _M.handle_error(wrpc_peer, payload)
  local etype = payload.error and payload.error.etype or "--"
  local errdesc = payload.error and payload.error.description or "--"
  ngx_log(NOTICE, string.format(
    "[wRPC] Received error message, %s.%s:%s (%s: %q)",
    payload.svc_id, payload.rpc_id, payload.ack, etype, errdesc
  ))

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_future = wrpc_peer.responses[ack]
    if response_future then
      if response_future.deadline and response_future.deadline < ngx_now() then
        if response_future.expire then
          response_future:expire()
        end

      else
        assert(response_future.error,
          "response future does not has a error handler!")
        response_future:error(etype, errdesc)
      end

    else
      ngx_log(ERR, 
        "reciving error response for a call not initiated by this peer.",
        " Service ID: ", payload.svc_id, " RPC ID: ", payload.rpc_id)
      local rpc = wrpc_peer.service:get_rpc(payload.svc_id .. payload.rpc_id)
      if rpc and rpc.error_handler then
        local ok, err = pcall(rpc.error_handler, wrpc_peer, etype, errdesc)
        if not ok then
          ngx_log(ERR, "error thrown when handling RPC error: ", err)
        end
      end
    end
  end
end

return _M