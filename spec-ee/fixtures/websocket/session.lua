-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers    = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local const      = require "spec-ee.fixtures.websocket.constants"
local cjson      = require "cjson"
local assert     = require "luassert"
local pl_file    = require "pl.file"

---@class ws.session
---@field client ws.test.client
---@field server ws.test.client
---@field request ws.request.info
---@field id string
---@field timeout integer
---@field server_echo boolean
local session = {}
session.__index = session

session.actions = require "spec-ee.fixtures.websocket.action"

local fmt = string.format
local rep = string.rep
local concat = table.concat


---@return string
local function get_error_log()
  local log = helpers.get_running_conf().nginx_err_logs
  if not log then
    return "NO ERROR LOG FILE FOUND!"
  end

  local content, err = pl_file.read(log)
  if err then
    return "FAILED READING ERROR LOG: " .. tostring(err or "unknown error")

  elseif content == nil or content == "" then
    return "ERROR LOG IS EMPTY!"
  end

  local lines = { "error.log contents:" ,
                 rep("-", 80),
                 content,
                 rep("-", 80) }

  return concat(lines, "\n")
end


---
-- Validate WebSocket session activity.
--
--
-- @see `spec-ee.fixtures.websocket.action` for action examples
--
--
---@param actions ws.session.action[]
function session:assert(actions)
  local len = #actions
  for i, act in ipairs(actions) do
    local target
    if act.target == "session" then
      target = self
    else
      target = self[act.target]
    end

    local ok, err = act.fn(target, self)

    local extra = ""
    if not ok then
      extra = get_error_log()
    end

    assert(ok, fmt(
      "\nsession: %s\nposition: %s/%s\naction: %s\ntarget: %s\nerror:\n\t%q\n%s",
      self.id, i, len, act.name, act.target, err, extra
    ))
  end
end

---
-- Close/teardown the WebSocket session.
--
-- This method is intended for post-test cleanup and does not perform
-- error-checking or attempt to gracefully close the connection.
function session:close()
  self.client:close()
  self.server:close()
end

---@class ws.test.session.opts : ws.test.client.opts
---@field idle_timeout number

---
-- Initialize a mock WebSocket connection.
--
-- This accepts an optional table of options, which are passed to the client
-- constructor (`spec-ee.helpers.ws_proxy_client`). It returns a table with
-- two WS client objects ("client" and "server") as well as a table containing
-- the details of the client handshake request.
--
---@param opts ws.test.session.opts
---@return ws.session
return function(opts)
  opts = opts or {}

  local idle_timeout = opts.idle_timeout or 5000

  ngx.log(ngx.INFO, "connecting to session listen endpoint")

  local server = ee_helpers.ws_client({
    scheme        = "ws",
    path          = "/session/listen",
    port          = const.ports.ws,
    fail_on_error = true,
    query         = { idle_timeout = idle_timeout },
  })

  local id = server.id
  ngx.log(ngx.INFO, "connected to session listen endpoint: ", id)

  opts.query = opts.query or {}
  opts.path = "/session/client"
  opts.timeout = opts.timeout or 500
  opts.query.session = id

  ngx.log(ngx.INFO, "connecting to session client endpoint")

  local client = ee_helpers.ws_proxy_client(opts)

  ngx.log(ngx.INFO, "connected to session client endpoint")

  ngx.log(ngx.INFO, "receiving handshake from upstream client")
  server.client.sock:settimeouts(nil, nil, 500)
  local data, typ, err = server:recv_frame()

  assert.is_nil(err, "failed receiving initial connect frame: " .. tostring(err))
  assert.equals("text", typ, "invalid initial frame type: " .. typ)
  assert.equals("string", type(data), "invalid data returned from connection")
  assert.truthy(#data > 0, "empty payload in initial connect frame")

  local request = cjson.decode(data)

  server.client.sock:settimeouts(nil, nil, opts.timeout)

  ngx.log(ngx.INFO, "session initialized")

  return setmetatable({
    client  = client,
    server  = server,
    request = request,
    id      = server.id,
    timeout = opts.timeout,
  }, session)
end
