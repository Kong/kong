-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local const = require "spec-ee.fixtures.websocket.constants"

local fmt = string.format
local find = string.find
local re_find = ngx.re.find
local OPCODES = const.opcode
local sleep = ngx.sleep

---
-- WebSocket "actions" represent small pieces of code that are to be
-- consumed/executed by the `spec-ee.fixtures.websocket.session` module in
-- order to validate correct behavior.
--
-- They consist of a name, callback function, and a target identifier. The target
-- informs the session of the object that is to be passed in to the callback
-- function--one of `client`, `server`, or `session` (for "meta" actions that
-- act upon the session object itself).
--
-- Action callbacks should return `true` on success or `nil` and an error string
-- on failure.
--
-- Example:
--
-- ```lua
-- session:assert({
--   {
--     name = "send_ping",
--     target = "client",
--     fn = function(client)
--        if client:send_ping("ping") then
--          return true
--        end
--        return nil, "failed sending ping"
--     end,
--   }
-- })
--
---@class ws.session.action
---@field name string
---@field target '"server"'|'"client"'|'"session"'
---@field fn ws.session.action.callback

---@alias ws.session.action.callback fun(target:ws.test.client|ws.session, ...):boolean|nil, string|nil

---@alias ws.session.action.factory fun(...):ws.session.action

---@alias ws.session.action.collection table<string, ws.session.action.factory>

local function is_timeout(err)
  return type(err) == "string" or find(err, "timeout") ~= nil
end

local function is_closed(err)
  return type(err) == "string" and find(err, "closed") ~= nil
end

local function is_fin(err)
  return err ~= "again"
end

---@param ws ws.test.client
---@return boolean ok
---@return string? error
local function recv_any(ws)
  local data, _, err = ws:recv_frame()
  return data ~= nil, err
end

---@param timeout integer
---@return ws.session.action.callback
local function recv_timeout(timeout)
  ---@param ws ws.test.client
  ---@param session ws.session
  ---@return boolean ok
  ---@return string? error
  return function(ws, session)
    if timeout then
      ws.client.sock:settimeouts(nil, nil, timeout)
    end

    local data, typ, err = ws:recv_frame()

    if timeout then
      ws.client.sock:settimeouts(nil, nil, session.timeout)
    end

    if data ~= nil then
      return nil, fmt("expected timeout but received %s frame", typ)
    end

    if not is_timeout(err) then
      return nil, fmt("expected timeout but received non-timeout error: %q", err)
    end

    return true
  end
end

---@param exp_err string
---@return ws.session.action.callback
local function recv_error(exp_err)
  assert(type(exp_err) == "string", "expected error string is required")

  ---@param ws ws.test.client
  return function(ws)
    local data, typ, err = ws:recv_frame()
    if data ~= nil then
      return nil, fmt("expected error but received %s frame", typ)
    end

    if is_timeout(err) then
      return nil, "expected error but received timeout"
    end

    if not re_find(err, exp_err, "oj") then
      return nil, fmt("receied error (%q) did not match %q", err, exp_err)
    end

    return true
  end
end


---@type ws.session.action.callback
---@param ws ws.test.client
---@param check_err? boolean
local function close_conn(ws, check_err)
  local ok, err = ws:close()

  if not ok and check_err and not is_closed(err) then
    return nil, fmt("ws client did not close cleanly: %q", err)
  end

  return true
end


---@param ws ws.test.client
---@param exp_type resty.websocket.protocol.type
---@param exp_data? string
---@param exp_status? integer
local function recv_type(ws, exp_type, exp_data, exp_status)
  local data, typ, err = ws:recv_frame()
  if not data then
    if is_timeout(err) then
      return nil, fmt("expected %s frame but got timeout", exp_type)

    elseif is_closed(err) then
      return nil, fmt("expected %s frame but connection is closed", exp_type)
    end

    return nil, fmt("expected %s frame but got an error: %q", exp_type, err)

  elseif typ ~= exp_type then
    return nil, fmt("expected %s frame but got %s frame", exp_type, typ)

  elseif exp_data and data ~= exp_data then
    return nil, fmt("expected payload: %q, received: %q", exp_data, data)

  elseif typ == "close"
    and exp_status
    and exp_status ~= err
    then
      return nil, fmt("expected close status %s but received %s", exp_status, err)

  end

  return true
end


---@param target '"client"'|'"server"'
---@param exp_type resty.websocket.protocol.type
---@param exp_data? string
---@param exp_status? integer
---@return ws.session.action
local function receiver(target, exp_type, exp_data, exp_status)
  return {
    name = "recv_" .. exp_type,
    target = target,
    ---@param ws ws.test.client
    fn = function(ws)
      return recv_type(ws, exp_type, exp_data, exp_status)
    end,
  }
end

---@param target '"client"'|'"server"'
---@param fn string
---@param data? string
---@param status? integer
---@return ws.session.action
local function sender(target, fn, data, status)
  return {
    name = fn,
    target = target,
    fn     = function(ws)
      return ws[fn](ws, data, status)
    end,
  }
end

---@param ws ws.test.client
---@param exp_typ? resty.websocket.protocol.type
local function handle_echo(ws, exp_typ)
  local data, typ, err = ws:recv_frame()
  if not data then
    return nil, fmt("expected %s frame but got error: %q", exp_typ, err)

  elseif exp_typ and typ ~= exp_typ then
    return nil, fmt("expected %s frame but got %s frame", exp_typ, typ)
  end

  local sent
  if typ == "ping" then
    sent, err = ws:send_pong(data)

  elseif typ == "pong" then
    sent, err = ws:send_pong(data)

  elseif typ == "close" then
    sent, err = ws:send_close(data, err)

  else
    local fin = is_fin(err)
    local opcode = OPCODES[typ]
    sent, err = ws:send_frame(fin, opcode, data)
  end

  if not sent then
    return nil, fmt("failed sending echo response: %q", err)
  end

  return true
end


local function echoer(typ, data, status)
  local exp_type = typ
  if     typ == "ping" then exp_type = "pong"
  elseif typ == "pong" then exp_type = "ping"
  end

  return {
    name = "echo_" .. typ,
    target = "session",
    ---@param sess ws.session
    fn = function(sess)
      local client = sess.client
      local fn = client["send_" .. typ]
      local ok, err = fn(client, data, status)
      if not ok then
        return nil, err
      end

      if sess.server_echo then
        ok, err = handle_echo(sess.server, typ)
        if not ok then
          return nil, err
        end
      end

      return recv_type(client, exp_type, data, status)
    end,
  }
end


---@param target '"client"'|'"server"'
local function send_actions(target)
  return {
    ---
    -- Send a ping frame
    --
    ---@param data? string
    ---@return ws.session.action
    ping = function(data)
      return sender(target, "send_ping", data)
    end,

    ---
    -- Send a pong frame
    --
    ---@param data? string
    ---@return ws.session.action
    pong = function(data)
      return sender(target, "send_pong", data)
    end,

    ---
    -- Send a text frame
    --
    ---@param data string
    ---@return ws.session.action
    text = function(data)
      return sender(target, "send_text", data)
    end,

    ---
    -- Send a binary frame
    --
    ---@param data string
    ---@return ws.session.action
    binary = function(data)
      return sender(target, "send_binary", data)
    end,

    ---
    -- Send a close frame
    --
    ---@param data? string
    ---@param status? integer
    ---@return ws.session.action
    close = function(data, status)
      return sender(target, "send_close", data, status)
    end,


    ---
    -- Send a continuation frame
    --
    ---@param data string
    ---@return ws.session.action
    continue = function(data)
      return sender(target, "send_continue", data)
    end,

    ---
    -- Send the first frame of a fragmented text message
    --
    ---@param data string
    ---@return ws.session.action
    text_fragment = function(data)
      return sender(target, "init_text_fragment", data)
    end,

    ---
    -- Send the first frame of a fragmented binary message
    --
    ---@param data string
    ---@return ws.session.action
    binary_fragment = function(data)
      return sender(target, "init_binary_fragment", data)
    end,

    ---
    -- Send the final frame of a fragmented message
    --
    ---@param data string
    ---@return ws.session.action
    final_fragment = function(data)
      return sender(target, "send_final_fragment", data)
    end,
  }
end

---@param target '"client"'|'"server"'
local function recv_actions(target)
  return {
    ---
    -- Expect a text frame and validate its payload
    --
    ---@param data string
    text = function(data)
      return receiver(target, "text", data)
    end,

    ---
    -- Expect a binary frame and validate its payload
    --
    ---@param data string
    binary = function(data)
      return receiver(target, "binary", data)
    end,

    ---
    -- Expect a ping frame and validate its payload
    --
    ---@param data string
    ping = function(data)
      return receiver(target, "ping", data)
    end,

    ---
    -- Expect a pong frame and validate its payload
    --
    ---@param data string
    pong = function(data)
      return receiver(target, "pong", data)
    end,

    ---
    -- Expect a continuation frame and validate its payload
    --
    ---@param data string
    continue = function(data)
      return receiver(target, "continue", data)
    end,

    ---
    -- Expect a close frame and validate its payload and status code
    --
    ---@param data? string
    ---@param status? integer
    close = function(data, status)
      return receiver(target, "close", data, status)
    end,


    ---
    -- Recieve a single frame of any type
    ---@return ws.session.action
    any = function()
      return {
        target = target,
        fn = recv_any,
      }
    end,

    ---
    -- Call recv_frame() and ensure that the read operation times out
    -- with no frame having been received
    --
    ---@param timeout? integer
    ---@return ws.session.action
    timeout = function(timeout)
      return {
        target = target,
        fn = recv_timeout(timeout),
      }
    end,

    ---
    -- Call recv_frame() and expect an error
    --
    ---@param err string
    ---@return ws.session.action
    error = function(err)
      return {
        target = target,
        fn = recv_error(err),
      }
    end,
  }
end

---@param target '"client"'|'"server"'
---@return ws.session.action.factory
local function close_action(target)
  ---
  -- Close the WebSocket connection
  return function()
    return {
      name = "close",
      target = target,
      fn = close_conn,
    }
  end
end


local function server_echo()
  local t = {
    ---
    -- Enable automatic echo replies from the server
    enable = function()
      return {
        name = "enable_echo",
        target = "session",
        fn = function(sess)
          sess.server_echo = true
          return true
        end,
      }
    end,

    ---
    -- Disable automatic echo replies from the server
    disable = function()
      return {
        name = "disable_echo",
        target = "session",
        fn = function(sess)
          sess.server_echo = false
          return true
        end,
      }
    end,
  }

  setmetatable(t, {
    __call = function()
      return {
        name = "echo",
        target = "server",
        fn = function(ws)
          return handle_echo(ws)
        end,
      }
    end,
  })

  return t
end

local function client_echo()
  return {
    ---
    -- Send a text frame from the client and validate that the server echoes it
    -- back to us.
    ---@param data string
    text = function(data)
      return echoer("text", data)
    end,

    ---
    -- Send a binary frame from the client and validate that the server echoes it
    -- back to us.
    ---@param data string
    binary = function(data)
      return echoer("binary", data)
    end,

    ---
    -- Send a ping frame from the client and validate that the server responds
    -- with a matching pong frame
    ---@param data? string
    ping = function(data)
      return echoer("ping", data)
    end,

    ---
    -- Send a close frame from the client and validate that the server responds
    -- with a matching close frame
    ---@param data? string
    ---@param status? integer
    close = function(data, status)
      return echoer("close", data, status)
    end,
  }
end


local function client_actions()
  return {
    send = send_actions("client"),
    recv = recv_actions("client"),
    close = close_action("client"),
    echo = client_echo(),
  }
end

local function server_actions()
  return {
    send = send_actions("server"),
    recv = recv_actions("server"),
    close = close_action("server"),
    echo = server_echo(),
  }
end


local actions = {
  client = client_actions(),
  server = server_actions(),
  echo = client_echo(),

  ---
  -- Gracefully close the session.
  close = function()
    return {
      name = "graceful_close",
      target = "session",
      ---@param sess ws.session
      fn = function(sess)
        sess.server:send_close()
        sess.client:recv_frame()
        sess.client:send_close()
        sess.server:recv_frame()
        sess.server:close()
        sess.client:close()
        return true
      end,
    }
  end,

  ---@type ws.session.action.factory
  ---@param duration number
  sleep = function(duration)
    return {
      name = "sleep",
      target = "session",
      fn = function()
        sleep(duration)
        return true
      end,
    }
  end,

  ---@type ws.session.action.factory
  ---@param timeout integer
  set_recv_timeout = function(timeout)
    return {
      name = "set_recv_timeout",
      target = "session",
      ---@param session ws.session
      fn = function(session)
        session.client.client.sock:settimeouts(nil, nil, timeout)
        session.server.client.sock:settimeouts(nil, nil, timeout)
        return true
      end,
    }
  end,
}

-- The labels `client` and `server` were chosen because they are the same
-- string length, and the alignment makes tests more readable:
--
-- local client, server = actions.client, actions.server
-- session:assert({
--    client.send.text("hi"),
--    server.recv.text("hi"),
-- })
--
-- In many other contexts, we use `upstream` instead of `server`, so having
-- an alias for it helps when constructing parameterized tests:
--
-- for src, dst in pairs({ client = "upstream", upstream = "client"}) do
--   session:assert({
--     actions[src].send.text("hi"),
--     actions[dst].recv.text("hi"),
--   })
-- end
--
actions.upstream = actions.server


return actions
