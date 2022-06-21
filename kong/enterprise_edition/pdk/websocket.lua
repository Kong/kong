-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local private = require "kong.enterprise_edition.pdk.private.websocket"
local phase_checker = require "kong.pdk.private.phases"
local const = require "kong.enterprise_edition.constants"

local get_state = private.get_state
local check_phase = phase_checker.check
local type = type
local ngx = ngx
local co_running = coroutine.running

local MAX_PAYLOAD_SIZE = const.WEBSOCKET.MAX_PAYLOAD_SIZE

local ws_proxy = phase_checker.new(phase_checker.phases.ws_proxy)
local ws_handshake = phase_checker.new(phase_checker.phases.ws_handshake)


local function ws_proxy_method(role, fn)
  local ns = "kong.websocket." .. role

  return function(...)
    check_phase(ws_proxy)

    local ctx = ngx.ctx
    local state = get_state(ctx, role)

    -- WebSocket frame callbacks each run in their own thread--one for the
    -- the client and one for the server. Allowing client functions to be
    -- invoked in the upstream context (and vice versa) would invite lots of
    -- weird, undefined, buggy behavior, so we gate things by checking the
    -- current thread. This will no doubt break if a plugin creates a new
    -- thread and calls a PDK function, but we'll consider than unsupported
    -- case for now.
    --
    -- XXX this feels kinda clunky, but our options are limited if we want
    -- to keep everything thread-safe without locking. Another option might be
    -- passing the PDK namespace into the plugin handler:
    --
    -- local pdk = kong.websocket.client
    -- for plugin, conf in iterator:iterate("ws_client_frame", ctx) do
    --   plugin.handler.ws_client_frame(plugin, conf, pdk)
    -- end
    --
    if state.thread ~= co_running() then
      error("calling " .. ns .. " method from the wrong thread", 2)
    end

    return fn(state, ...)
  end
end


local function ws_handshake_method(role, fn)
  return function(...)
    check_phase(ws_handshake)
    return fn(ngx.ctx, role, ...)
  end
end


local function set_max_payload_size(ctx, role, size)
  if type(size) ~= "number" then
    error("`size` must be a number", 2)

  elseif size > MAX_PAYLOAD_SIZE then
    error("`size` must be <= " .. tostring(MAX_PAYLOAD_SIZE), 2)

  elseif size < 0 then
    error("`size` must be >= 0", 2)
  end

  local key = role == "client"
              and "KONG_WEBSOCKET_CLIENT_MAX_PAYLOAD_SIZE"
              or  "KONG_WEBSOCKET_UPSTREAM_MAX_PAYLOAD_SIZE"

  -- size of 0 sets back to the default
  if size == 0 then
    size = nil
  end

  ctx[key] = size
end


local function get_frame(state)
  return state.data, state.type, state.status
end


local function set_frame_data(state, data)
  if type(data) ~= "string" then
    error("frame payload must be a string", 2)
  end
  state.data = data
end


local function set_status(state, code)
  -- resty.websocket validates the status code before constructing a close
  -- frame, so we're covered at the low level, but this covers the most
  -- trivial type of invalid usage
  if type(code) ~= "number" then
    error("status code must be an integer", 2)
  end

  if state.type ~= "close" then
    error("cannot override status code of non-close frame", 2)
  end

  state.status = code
end


local function drop_frame(state)
  if state.type == "close" then
    error("cannot drop a close frame", 2)
  end
  state.drop = true
end


local function close(state, status, message, peer_status, peer_message)
  local role = state.role
  local peer
  if role == "client" then
    peer = "upstream"
  else
    peer = "client"
  end

  if status ~= nil then
    if type(status) ~= "number" then
      error(role .. " status must be nil or a number", 2)
    end
    state.status = status
  end

  if message ~= nil then
    if type(message) ~= "string" then
      error(role .. " message must be nil or a string", 2)
    end
    state.data = message
  end

  if peer_status ~= nil then
    if type(peer_status) ~= "number" then
      error(peer .. " status must be nil or a number", 2)
    end
    state.peer_status = peer_status
  end

  if peer_message ~= nil then
    if type(peer_message) ~= "string" then
      error(peer .. " message must be nil or a string", 2)
    end
    state.peer_data = peer_message
  end

  -- lua-resty-websocket-proxy doesn't really let us communicate
  -- "send a close frame _after_ forwarding the existing frame" as an
  -- intent, so drop+close is hardcoded for now
  state.drop = true

  state.closing = true
end


local function new()

  ---
  -- WebSocket PDK
  --
  -- @module kong.websocket
  local pdk = {

    ---
    -- Client WebSocket PDK functions.
    --
    -- @module kong.websocket.client
    client = {
      ---
      -- Retrieve the current frame.
      --
      -- This returns the payload, type, and status code (for close frames) of
      -- the in-flight frame/message.
      --
      -- This function is useful in contexts like the pre/post-function plugins
      -- where execution is sandboxed, and the caller no access to these
      -- variables in the plugin handler scope.
      --
      -- @function kong.websocket.client.get_frame
      -- @phases ws_client_frame
      -- @treturn string The frame payload.
      -- @treturn string The frame type (one of "text", "binary", "ping",
      --   "pong", or "close")
      -- @treturn number The frame status code (only returned for close frames)
      -- @usage
      -- local data, typ, status = kong.websocket.client.get_frame()
      get_frame = ws_proxy_method("client", get_frame),


      ---
      -- Set the current frame's payload.
      --
      -- This allows the caller to overwrite the contents of the in-flight
      -- WebSocket frame before it is forwarded upstream.
      --
      -- Plugin handlers that execute _after_ this has been called will see the
      -- updated version of the frame.
      --
      -- @function kong.websocket.client.set_frame_data
      -- @phases ws_client_frame
      -- @tparam string data The desired frame payload
      -- @usage
      -- kong.websocket.client.set_frame_data("updated!")
      set_frame_data = ws_proxy_method("client", set_frame_data),


      ---
      -- Set the status code for a close frame.
      --
      -- This allows the caller to overwrite the status code of close frame
      -- before it is forwarded upstream.
      --
      -- See the [WebSocket RFC](https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.1)
      -- for a list of valid status codes.
      --
      -- Plugin handlers that execute _after_ this has been called will see the
      -- updated version of the status code.
      --
      -- Calling this function when the in-flight frame is not a close frame
      -- will result in an exception.
      --
      -- @function kong.websocket.client.set_status
      -- @tparam number status The desired status code
      -- @usage
      -- -- overwrite the payload and status before forwarding
      -- local data, typ, status = kong.websocket.client.get_frame()
      -- if typ == "close" then
      --   kong.websocket.client.set_frame_data("goodbye!")
      --   kong.websocket.client.set_status(1000)
      -- end
      set_status = ws_proxy_method("client", set_status),


      ---
      -- Drop the current frame.
      --
      -- This causes the in-flight frame to be dropped, meaning it will not be
      -- forwarded upstream.
      --
      -- Plugin handlers that are set to execute _after_ this one will be
      -- skipped.
      --
      -- Close frames cannot be dropped. Calling this function for a close
      -- frame will result in an exception.
      -- @function kong.websocket.client.drop_frame
      -- @usage
      -- kong.websocket.client.drop_frame()
      drop_frame = ws_proxy_method("client", drop_frame),


      ---
      -- Close the WebSocket connection.
      --
      -- Calling this function immediately sends a close frame to the client and
      -- the upstream before terminating the connection.
      --
      -- The in-flight frame will not be forwarded upstream, and plugin
      -- handlers that are set to execute _after_ the current one will not be
      -- executed.
      --
      -- @function kong.websocket.client.close
      -- @tparam[opt] number status Status code of the client close frame
      -- @tparam[opt] string message Payload of the client close frame
      -- @tparam[opt] number upstream_status Status code of the upstream close frame
      -- @tparam[opt] string upstream_payload Payload of the upstream close frame
      -- @usage
      -- kong.websocket.client.close(1009, "Invalid message",
      --                             1001, "Client is going away")
      close = ws_proxy_method("client", close),


      ---
      -- Set the maximum allowed payload size for client frames, in bytes.
      --
      -- This limit is applied to all data frame types:
      --   * text
      --   * binary
      --   * continuation
      --
      -- The limit is also assessed during aggregation of frames. For example,
      -- if the limit is 1024, and a client sends 3 continuation frames of size
      -- 500 each, the third frame will exceed the limit.
      --
      -- If a client sends a message that exceeds the limit, a close frame with
      -- status code `1009` is sent to the client, and the connection is closed.
      --
      -- This limit does not apply to control frames (close/ping/pong).
      --
      -- @tparam integer size The limit (`0` resets to the default limit)
      -- @usage
      -- -- set a max payload size of 1KB
      -- kong.websocket.client.set_max_payload_size(1024)
      --
      -- -- Restore the default limit
      -- kong.websocket.client.set_max_payload_size(0)
      set_max_payload_size = ws_handshake_method("client", set_max_payload_size),
    },

    ---
    -- Upstream WebSocket PDK functions.
    --
    -- @module kong.websocket.upstream
    upstream = {
      ---
      -- Retrieve the current frame.
      --
      -- This returns the payload, type, and status code (for close frames) of
      -- the in-flight frame/message.
      --
      -- This function is useful in contexts like the pre/post-function plugins
      -- where execution is sandboxed, and the caller no access to these
      -- variables in the plugin handler scope.
      --
      -- @function kong.websocket.upstream.get_frame
      -- @phases ws_upstream_frame
      -- @treturn string The frame payload.
      -- @treturn string The frame type (one of "text", "binary", "ping",
      --   "pong", or "close")
      -- @treturn number The frame status code (only returned for close frames)
      -- @usage
      -- local data, typ, status = kong.websocket.upstream.get_frame()
      get_frame = ws_proxy_method("upstream", get_frame),


      ---
      -- Set the current frame's payload.
      --
      -- This allows the caller to overwrite the contents of the in-flight
      -- WebSocket frame before it is forwarded to the client.
      --
      -- Plugin handlers that execute _after_ this has been called will see the
      -- updated version of the frame.
      --
      -- @function kong.websocket.upstream.set_frame_data
      -- @phases ws_upstream_frame
      -- @tparam string data The desired frame payload
      -- @usage
      -- kong.websocket.upstream.set_frame_data("updated!")
      set_frame_data = ws_proxy_method("upstream", set_frame_data),


      ---
      -- Set the status code for a close frame.
      --
      -- This allows the caller to overwrite the status code of close frame
      -- before it is forwarded to the client.
      --
      -- See the [WebSocket RFC](https://datatracker.ietf.org/doc/html/rfc6455#section-7.4.1)
      -- for a list of valid status codes.
      --
      -- Plugin handlers that execute _after_ this has been called will see the
      -- updated version of the status code.
      --
      -- Calling this function when the in-flight frame is not a close frame
      -- will result in an exception.
      --
      -- @function kong.websocket.upstream.set_status
      -- @tparam number status The desired status code
      -- @usage
      -- -- overwrite the payload and status before forwarding
      -- local data, typ, status = kong.websocket.upstream.get_frame()
      -- if typ == "close" then
      --   kong.websocket.upstream.set_frame_data("goodbye!")
      --   kong.websocket.upstream.set_status(1000)
      -- end
      set_status = ws_proxy_method("upstream", set_status),


      ---
      -- Drop the current frame.
      --
      -- This causes the in-flight frame to be dropped, meaning it will not be
      -- forwarded to the client.
      --
      -- Plugin handlers that are set to execute _after_ this one will be
      -- skipped.
      --
      -- Close frames cannot be dropped. Calling this function for a close
      -- frame will result in an exception.
      -- @function kong.websocket.upstream.drop_frame
      -- @usage
      -- kong.websocket.upstream.drop_frame()
      drop_frame = ws_proxy_method("upstream", drop_frame),


      ---
      -- Close the WebSocket connection.
      --
      -- Calling this function immediately sends a close frame to the client and
      -- the upstream before terminating the connection.
      --
      -- The in-flight frame will not be forwarded to the client, and plugin
      -- handlers that are set to execute _after_ the current one will not be
      -- executed.
      --
      -- @function kong.websocket.upstream.close
      -- @tparam[opt] number status Status code of the upstream close frame
      -- @tparam[opt] string message Payload of the upstream close frame
      -- @tparam[opt] number client_status Status code of the client close frame
      -- @tparam[opt] string client_payload Payload of the client close frame
      -- @usage
      -- kong.websocket.upstream.close(1009, "Invalid message",
      --                               1001, "Upstream is going away")
      close = ws_proxy_method("upstream", close),


      ---
      -- Set the maximum allowed payload size for upstream frames.
      --
      -- This limit is applied to all data frame types:
      --   * text
      --   * binary
      --   * continuation
      --
      -- The limit is also assessed during aggregation of frames. For example,
      -- if the limit is 1024, and a upstream sends 3 continuation frames of size
      -- 500 each, the third frame will exceed the limit.
      --
      -- If a upstream sends a message that exceeds the limit, a close frame with
      -- status code `1009` is sent to the upstream, and the connection is closed.
      --
      -- This limit does not apply to control frames (close/ping/pong).
      --
      -- @tparam integer size The limit (`0` resets to the default limit)
      -- @usage
      -- -- set a max payload size of 1KB
      -- kong.websocket.upstream.set_max_payload_size(1024)
      --
      -- -- Restore the default limit
      -- kong.websocket.upstream.set_max_payload_size(0)
      set_max_payload_size = ws_handshake_method("upstream", set_max_payload_size),
    },
  }

  return pdk
end

return {
  new = new,
}
