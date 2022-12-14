local pb = require "pb"
local message = require "kong.tools.wrpc.message"

local table_unpack = table.unpack -- luacheck: ignore
local pb_decode = pb.decode

local ngx_now = ngx.now
local ngx_log = ngx.log
local NOTICE = ngx.NOTICE
local exiting = ngx.worker.exiting
local sleep = ngx.sleep
local thread_spawn = ngx.thread.spawn
local thread_kill = ngx.thread.kill
local thread_wait = ngx.thread.wait

local process_message = message.process_message
local handle_error = message.handle_error
local send_error = message.send_error

-- utility functions

local function endswith(s, e) -- luacheck: ignore
  return s and e and e ~= "" and s:sub(#s - #e + 1, #s) == e
end

--- return same args in the same order, removing any nil args.
--- required for functions (like ngx.thread.wait) that complain
--- about nil args at the end.
local function safe_args(...)
  local out = {}
  for i = 1, select('#', ...) do
    out[#out + 1] = select(i, ...)
  end
  return table_unpack(out)
end

local _M = {}

--- @async
local function step(wrpc_peer)
  local msg, err = wrpc_peer:receive()

  while msg ~= nil do
    msg = assert(pb_decode("wrpc.WebsocketPayload", msg))
    assert(msg.version == "PAYLOAD_VERSION_V1", "unknown encoding version")
    local payload = msg.payload

    if payload.mtype == "MESSAGE_TYPE_ERROR" then
      handle_error(wrpc_peer, payload)

    elseif payload.mtype == "MESSAGE_TYPE_RPC" then
      -- protobuf may confuse with 0 value and nil(undefined) under some set up
      -- so we will just handle 0 as nil
      local ack = payload.ack or 0
      local deadline = payload.deadline or 0

      if ack == 0 and deadline < ngx_now() then
        ngx_log(NOTICE,
          "[wRPC] Expired message (", deadline, "<", ngx_now(), ") discarded")

      elseif ack ~= 0 and deadline ~= 0 then
        ngx_log(NOTICE,
          "[WRPC] Invalid deadline (", deadline, ") for response")

      else
        process_message(wrpc_peer, payload)
      end

    else
      send_error(wrpc_peer, payload, {
        etype = "ERROR_TYPE_GENERIC",
        description = "Unsupported message type",
      })
    end

    msg, err = wrpc_peer:receive()
  end

  if err ~= nil and not endswith(err, ": timeout") then
    ngx_log(NOTICE, "[wRPC] WebSocket frame: ", err)
    wrpc_peer.closing = true
    return false, err
  end
  
  return true
end

function _M.spawn(wrpc_peer)
  wrpc_peer._receiving_thread = assert(thread_spawn(function()
    while not exiting() and not wrpc_peer.closing do
      local ok = step(wrpc_peer)
      -- something wrong with this step
      -- let yield instead of retry immediately
      if not ok then
        sleep(0)
      end
    end
  end))

  if wrpc_peer.request_queue then
    wrpc_peer._transmit_thread = assert(thread_spawn(function()
      while not exiting() and not wrpc_peer.closing do
        local data, err = wrpc_peer.request_queue:pop()
        if data then
          wrpc_peer.conn:send_binary(data)
        end

        if not data and err ~= "timeout" then
          return nil, err
        end
      end
    end))
  end
end

function _M.wait(wrpc_peer)
  local ok, err, perr = thread_wait(safe_args(
    wrpc_peer._receiving_thread,
    wrpc_peer._transmit_thread
  ))

  if wrpc_peer._receiving_thread then
    thread_kill(wrpc_peer._receiving_thread)
    wrpc_peer._receiving_thread = nil
  end

  if wrpc_peer._transmit_thread then
    thread_kill(wrpc_peer._transmit_thread)
    wrpc_peer._transmit_thread = nil
  end

  return ok, err, perr
end

return _M
