-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require "cjson.safe"
local const = require "spec-ee.fixtures.websocket.constants"

local unpack = require("kong.tools.table").unpack
local log = ngx.log
local concat = table.concat
local insert = table.insert
local fmt = string.format

local NOTICE = ngx.NOTICE

---
-- RPC Plugin fixture
--
-- This fixture is designed around turning the pre-function/post-function
-- plugins into somewhat of an RPC tool for WebSocket connections.
--
-- It consists of two main components:
--   * Functions that are called during websocket handlers (for instance, by
--     calling `require("spec-ee.fixtures.websocket.rpc").handler.ws_handshake()`
--     during the ws_handshake phase
--   * Helper functions for generating RPC call actions
--
-- The goal of all this is to enable easy testing of various PDK functions
-- inside the WebSocket plugin handlers.
--
local RPC = {}


---@alias ws.test.rpc.target
---| '"client"'
---| '"upstream"'
---| '"close"'


---@class ws.test.rpc.cmd : table
---@field target ws.test.rpc.target
---@field fn string
---@field args any[]
---@field eval string
---@field postpone boolean


---@param cmd ws.test.rpc.cmd
local function handler(cmd)
  if cmd.fn then
    local ref = _G
    cmd.fn:gsub("([^.]+)", function(k)
      assert(type(ref) == "table")
      ref = ref[k]
    end)

    assert(type(ref) == "function", tostring(cmd.fn) .. " is not a function")

    local args = cmd.args or {}

    log(NOTICE, "RPC ", cmd.target, " call: ", cmd.fn,
        ", args: ", concat(args, ","))

    return ref(unpack(args))

  elseif cmd.eval then
    log(NOTICE, "RPC ", cmd.target, " eval: ", cmd.eval)

    local fn = assert(loadstring(cmd.eval))
    return fn()
  end
end


---@param role '"client"'|'"upstream"'
local function ws_frame(role)
  local ws = kong.websocket[role]
  local ctx = kong.ctx.plugin

  local data, typ, status = ws.get_frame()

  local record = ctx.DATA[role]
  record.frames = record.frames + 1

  if typ == "close" then
    record.close_status = status or const.status.NO_STATUS.CODE
    record.close_reason = data ~= "" and data or const.status.NO_STATUS.REASON
  end

  ---@type ws.test.rpc.cmd
  local cmd

  -- check for any pending commands
  if ctx.pending and ctx.pending.target == role then
    ngx.log(NOTICE, "found a pending rpc command")
    cmd = ctx.pending
    ctx.pending = nil

    -- check the in-flight text frame for a command
  elseif typ == "text" then
    local decoded = cjson.decode(data)
    if type(decoded) == "table" and decoded.target then
      cmd = decoded
    end
  end

  if not cmd then
    return
  end

  -- schedule command for ws_close
  if cmd.target == "close" then
    local t = ctx.rpc_close or {}
    insert(t, cmd)
    ctx.rpc_close = t
    ws.drop_frame()
    return

    -- postpone command until next frame
    -- frame will be dropped
  elseif cmd.postpone then
    ngx.log(NOTICE, "postponing ", cmd.target, " command")
    cmd.postpone = nil
    ctx.pending = cmd

    ws.drop_frame()
    return

  elseif cmd.target ~= role then
    return
  end

  local res = handler(cmd)

  if res then
    ws.set_frame_data(tostring(res))
  end
end


---
-- RPC handler functions
--
-- These are wired in via pre-function/post-function expressions
RPC.handler = {
  ---
  -- Handshake handler for RPC plugin fixture
  ws_handshake = function()
    kong.response.set_header("ws-function-test", "hello")
    kong.ctx.plugin.DATA = {
      upstream = {
        frames = 0,
        close_status = const.status.NO_STATUS.CODE,
        close_reason = const.status.NO_STATUS.REASON,
      },
      client = {
        frames = 0,
        close_status = const.status.NO_STATUS.CODE,
        close_reason = const.status.NO_STATUS.REASON,
      },
    }
  end,

  ---
  -- Client frame handler for RPC plugin fixture
  ws_client_frame = function()
    return ws_frame("client")
  end,

  ---
  -- Upstream frame handler for RPC plugin fixture
  ws_upstream_frame = function()
    return ws_frame("upstream")
  end,

  ---
  -- Close handler for RPC plugin fixture
  ws_close = function()
    kong.log.set_serialize_value("ws", kong.ctx.plugin.DATA)

    local cmds = kong.ctx.plugin.rpc_close
    if cmds then
      for _, cmd in ipairs(cmds) do
        handler(cmd)
      end
    end
  end,
}


---
-- Create an RPC call action
--
---@param target ws.test.rpc.target
---@param postpone boolean
---@param fn string
---@vararg any
---@return ws.session.action
local function rpc_call(target, postpone, fn, ...)
  local name = "rpc_call"
  if postpone then
    name = name .. "_postpone"
  end

  local args
  if select("#", ...) > 0 then
    args = {}
    for i = 1, select("#", ...) do
      args[i] = select(i, ...)
    end
  end

  local payload = cjson.encode({
    target   = target,
    postpone = postpone,
    fn       = fn,
    args     = args,
  })

  return {
    name = name,
    target = "client",
    fn = function(ws)
      return ws:send_text(payload)
    end,
  }
end


---
-- Create an RPC eval action
--
---@param target ws.test.rpc.target
---@param postpone boolean
---@param code string
---@return ws.session.action
local function rpc_eval(target, postpone, code)
  local name = "rpc_eval"
  if postpone then
    name = name .. "_postpone"
  end

  local payload = cjson.encode({
    target = target,
    postpone = postpone,
    eval = code,
  })

  return {
    name = name,
    target = "client",
    fn = function(ws)
      return ws:send_text(payload)
    end
  }
end


local function make_rpc(target)
  return {
    ---
    -- Call the given function upon receipt of this frame
    --
    -- If the function returns a truth-y value, the payload of the current
    -- frame are replaced with this return value
    --
    --```lua
    --  session:assert({
    --    RPC.client.call("kong.request.get_scheme"),
    --    WS.server.recv.text("http"),
    --  })
    --```
    --
    ---@param fn string
    ---@vararg any
    call = function(fn, ...)
      return rpc_call(target, false, fn, ...)
    end,

    ---
    -- Evaluate the given lua expression upon receipt of this frame
    --
    -- If the expression returns truth-y value, the payload of the current
    -- frame are replaced with this return value
    --
    --```lua
    --  session:assert({
    --    RPC.client.eval("kong.ctx.plugin.foo = 1"),
    --    WS.server.recv.any(),
    --
    --    RPC.client.eval("return kong.ctx.plugin.foo"),
    --    WS.server.recv.text("1"),
    --  })
    --```
    --
    ---@param expr string
    eval = function(expr)
      return rpc_eval(target, false, expr)
    end,

    next = {
      ---
      -- Call the given function upon receipt of the _next_ frame.
      --
      -- The frame containing this RPC instruction will be dropped.
      --
      ---@param fn string
      ---@vararg any
      call = function(fn, ...)
        return rpc_call(target, true, fn, ...)
      end,

      ---
      -- Evaluate the given lua code upon receipt of the _next_ frame
      --
      -- The frame containing this RPC instruction will be dropped.
      --
      ---@param code string
      eval = function(code)
        return rpc_eval(target, true, code)
      end,
    }
  }
end


---
-- RPC client frame actions
RPC.client = make_rpc("client")


---
-- RPC upstream frame actions
RPC.upstream = make_rpc("upstream")


---
-- RPC close actions
RPC.close = {
  ---
  -- Evaluate the given lua code during the ws_close phase
  --
  ---@param code string
  eval = function(code)
    return rpc_eval("close", false, code)
  end,
}


---
-- Generate a lua function string that writes to a temp file.
--
-- The body should be a lua expression.
--
-- The filename and function string are returned.
--
-- This was written with `RPC.close.eval()` in mind:
--
--```lua
--  local fname, writer = RPC.file_writer("kong.ctx.plugin.foo")
--
--  session:assert({
--    RPC.close.eval(writer)
--  })
--
--  session:close()
--
--  assert_file_exists(fname)
--  assert.equals("foo contents", read_file(fname))
--```
--
---@param body string
---@return string filename
---@return string writer
function RPC.file_writer(body)
  local fname = os.tmpname()

  -- in environments like gojira where busted and Kong run as different users,
  -- this file will be unwritable, so remove it first
  os.remove(fname)

  return fname, fmt([[
    local fname = %q
    local fh = assert(io.open(fname, "w+"))
    local content = %s
    ngx.log(ngx.WARN, "Writing '", content, "' to ", fname)
    assert(fh:write(content))
    fh:close()
  ]], fname, body)
end


-- Generate a lua function string that writes the output of
-- `kong.log.serialize()` to a temp file.
--
-- The filename and function string are returned
--
---@return string filename
---@return string writer
function RPC.log_writer()
  return RPC.file_writer([[require("cjson").encode(kong.log.serialize())]])
end


---
-- Generate an RPC config for the pre-function/post-function plugins
--
-- The optional `extra` param allows one to extend the config table before
-- returning it. If `extra` is a table, its contents are copied into the
-- final config. If `extra` is a function, it is called with the config as its
-- first argument, and the return value is used as the final config.
--
---@param extra? table|function
---@return table
function RPC.plugin_conf(extra)
  local conf = {
    ws_handshake = {[[
      require("spec-ee.fixtures.websocket.rpc").handler.ws_handshake()
    ]]},
    ws_client_frame = {[[
      require("spec-ee.fixtures.websocket.rpc").handler.ws_client_frame()
    ]]},
    ws_upstream_frame = {[[
      require("spec-ee.fixtures.websocket.rpc").handler.ws_upstream_frame()
    ]]},
    ws_close = {[[
      require("spec-ee.fixtures.websocket.rpc").handler.ws_close()
    ]]},
  }

  if type(extra) == "table" then
    for phase, items in pairs(extra) do
      conf[phase] = conf[phase] or {}
      for _, item in ipairs(items) do
        table.insert(conf[phase], item)
      end
    end

  elseif type(extra) == "function" then
    conf = extra(conf)
  end

  return conf
end


return RPC
