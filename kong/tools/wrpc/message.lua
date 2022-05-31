
local pb = require "pb"
local utils = require "kong.tools.wrpc.utils"
local table_unpack = table.unpack     -- luacheck: ignore

local encodearray = utils.encodearray
local decodearray = utils.decodearray
local ok_wrapper = utils.ok_wrapper

local pb_decode = pb.decode
local pb_encode = pb.encode

local ngx_log = ngx.log
local ERR = ngx.ERR
local NOTICE = ngx.NOTICE
local ngx_now = ngx.now

local _M = {}

--- Handle RPC data (mtype == MESSAGE_TYPE_RPC).
--- Could be an incoming method call or the response to a previous one.
--- @param payload table decoded payload field from incoming `wrpc.WebsocketPayload` message
function _M.process_message(wrpc_peer, payload)
  local rpc = wrpc_peer.service:get_rpc(payload.svc_id .. '.' .. payload.rpc_id)
  if not rpc then
    wrpc_peer:send_payload({
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
    local response_waiter = wrpc_peer.response_queue[ack]
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
      wrpc_peer.response_queue[ack] = nil

    elseif rpc.response_handler then
      pcall(rpc.response_handler, wrpc_peer, decodearray(pb_decode, rpc.output_type, payload.payloads))
    end

  else
    -- incoming method call
    if rpc.handler then
      local input_data = decodearray(pb_decode, rpc.input_type, payload.payloads)
      local ok, output_data = ok_wrapper(pcall(rpc.handler, wrpc_peer, table_unpack(input_data, 1, input_data.n)))
      if not ok then
        local err = tostring(output_data[1])
        ngx_log(ERR, ("[wrpc] Error handling %q method: %q"):format(rpc.name, err))
        wrpc_peer:send_payload({
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
      wrpc_peer:send_payload({
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
function _M.handle_error(wrpc_peer, payload)
  local etype = payload.error and payload.error.etype or "--"
  local errdesc = payload.error and payload.error.description or "--"
  ngx_log(NOTICE, string.format("[wRPC] Received error message, %s.%s:%s (%s: %q)",
    payload.svc_id, payload.rpc_id, payload.ack, etype, errdesc
  ))

  local ack = tonumber(payload.ack) or 0
  if ack > 0 then
    -- response to a previous call
    local response_waiter = wrpc_peer.response_queue[ack]
    if response_waiter and response_waiter.handle_error then

      if response_waiter.deadline and response_waiter.deadline < ngx_now() then
        if response_waiter.expire then
          response_waiter:expire()
        end

      else
        response_waiter:handle_error(etype, errdesc)
      end
      wrpc_peer.response_queue[ack] = nil

    else
      local rpc = wrpc_peer.service:get_method(payload.svc_id, payload.rpc_id)
      if rpc and rpc.error_handler then
        pcall(rpc.error_handler, wrpc_peer, etype, errdesc)
      end
    end
  end
end

return _M