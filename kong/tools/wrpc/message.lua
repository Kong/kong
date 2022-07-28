
local pb = require "pb"

local yield = require "kong.tools.utils".yield

local tonumber = tonumber

local pb_decode = pb.decode
local pb_encode = pb.encode

local ngx_log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE

local _M = {}

local function send_error(wrpc_peer, payload, error)
  local ok, err = wrpc_peer:send_payload({
    mtype = "MESSAGE_TYPE_ERROR",
    error = error,
    svc_id = payload.svc_id,
    rpc_id = payload.rpc_id,
    ack = payload.seq,
  })

  if not ok then
    return ok, err
  end

  return nil, error.description or "unspecified error"
end

_M.send_error = send_error

local empty_table = {}

local function handle_request(wrpc_peer, rpc, payload)
  if not rpc.handler then
    return send_error(wrpc_peer, payload, {
      etype = "ERROR_TYPE_INVALID_RPC",   -- invalid here, not in the definition
      description = "Unhandled method",
    })
  end

  local input_data = pb_decode(rpc.input_type, payload.payloads)
  local ok, output_data = pcall(rpc.handler, wrpc_peer, input_data)
  if not ok then
    local err = output_data
    ngx_log(ERR, ("[wrpc] Error handling %q method: %q"):format(rpc.name, err))

    return send_error(wrpc_peer, payload, {
      etype = "ERROR_TYPE_UNSPECIFIED",
      description = err,
    })
  end

  if not output_data then
    output_data = empty_table
  end

  return wrpc_peer:send_payload({
    mtype = "MESSAGE_TYPE_RPC", -- MESSAGE_TYPE_RPC,
    svc_id = rpc.svc_id,
    rpc_id = rpc.rpc_id,
    ack = payload.seq,
    payload_encoding = "ENCODING_PROTO3",
    payloads = pb_encode(rpc.output_type, output_data),
  })
end

local function handle_response(wrpc_peer, rpc, payload,response_future)
  -- response to a previous call
  if not response_future then
    local err = "receiving response for a call expired or not initiated by this peer."
    ngx_log(ERR, 
      err, " Service ID: ", payload.svc_id, " RPC ID: ", payload.rpc_id)
    pcall(rpc.response_handler,
      wrpc_peer, pb_decode(rpc.output_type, payload.payloads))
    return nil, err
  end

  if response_future:is_expire() then
    response_future:expire()
    return nil, "timeout"
  end

  response_future:done(pb_decode(rpc.output_type, payload.payloads))

  -- to prevent long delay
  yield()

  return true
end

--- Handle RPC data (mtype == MESSAGE_TYPE_RPC).
--- Could be an incoming method call or the response to a previous one.
--- @param payload table decoded payload field from incoming `wrpc.WebsocketPayload`
function _M.process_message(wrpc_peer, payload)
  local rpc = wrpc_peer.service:get_rpc(
    payload.svc_id .. '.' .. payload.rpc_id)
  if not rpc then
    return send_error(wrpc_peer, payload, {
      etype = "ERROR_TYPE_INVALID_SERVICE",
      description = "Invalid service (or rpc)",
    })
  end

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    local response_future = wrpc_peer.responses[ack]
    return handle_response(wrpc_peer, rpc, payload,response_future)

  -- protobuf can not tell 0 from nil so this is best we can do
  elseif ack == 0 then
    -- incoming method call
    return handle_request(wrpc_peer, rpc, payload)
  else
    local err = "receiving negative ack number"
    ngx_log(ERR, err, ":", ack)
    return nil, err
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
  if ack < 0 then
    local err = "receiving negative ack number"
    ngx_log(ERR, err, ":", ack)
    return nil, err
  end

  if ack == 0 then
    local err = "malformed wRPC message"
    ngx_log(ERR,
      err, " Service ID: ", payload.svc_id, " RPC ID: ", payload.rpc_id)

    return nil, err
  end

  -- response to a previous call
  local response_future = wrpc_peer.responses[ack]

  if not response_future then
    local err = "receiving error message for a call" ..
      " expired or not initiated by this peer."
    ngx_log(ERR, 
      err, " Service ID: ", payload.svc_id, " RPC ID: ", payload.rpc_id)

    local rpc = wrpc_peer.service:get_rpc(payload.svc_id .. payload.rpc_id)
    if not rpc then
      err = "receiving error message for unkonwn RPC"
      ngx_log(ERR,
        err, " Service ID: ", payload.svc_id, " RPC ID: ", payload.rpc_id)

      return nil, err
    end

    -- fall back to rpc error handler
    if rpc.error_handler then
      local ok, err = pcall(rpc.error_handler, wrpc_peer, etype, errdesc)
      if not ok then
        ngx_log(ERR, "error thrown when handling RPC error: ", err)
      end
    end
    return nil, err
  end

  if response_future:is_expire() then
    response_future:expire()
    return nil, "receiving error message response for timeouted request"
  end

  -- finally, we can handle the error without encountering more errors
  response_future:error(etype, errdesc)

  return true
end

return _M