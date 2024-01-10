-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

------------------------------------------------------------------
-- Collection of utilities to help testing Kong-Enterprise features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @module spec-ee.helpers
-- @usage
-- local helpers = require 'spec.helpers'
-- local eehelpers = require 'spec-ee.helpers'

local helpers     = require "spec.helpers"
local listeners = require "kong.conf_loader.listeners"
local cjson = require "cjson.safe"
local assert = require "luassert"
local utils = require "kong.tools.utils"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"
local pl_file = require "pl.file"


local _M = {}

--- Returns Redis Cluster nodes list.
-- The list can be configured in environment variable `KONG_SPEC_TEST_REDIS_CLUSTER_ADDRESSES`.
-- @function parsed_redis_cluster_addresses
-- @treturn table nodes list
-- @usage
-- ~ $ export KONG_SPEC_TEST_REDIS_CLUSTER_ADDRESSES=node-1:6379,node-2:6379,node-3:6379
--
-- local redis_cluster_addresses = parsed_redis_cluster_addresses()
function _M.parsed_redis_cluster_addresses()
  local env_cluster_addresses = os.getenv("KONG_SPEC_TEST_REDIS_CLUSTER_ADDRESSES")

  -- default
  if not env_cluster_addresses then
    return {  "localhost:7000", "localhost:7001", "localhost:7002" }
  end

  local redis_cluster_addresses = {}
  for node in string.gmatch(env_cluster_addresses, "[^,]+") do
    table.insert(redis_cluster_addresses, node)
  end

  return redis_cluster_addresses
end

--- Registers RBAC resources.
-- @param db db db object (see `spec.helpers.get_db_utils`)
-- @param ws_name (optional)
-- @param ws_table (optional)
-- @return on success: `super_admin, super_user_role`
-- @return on failure: `nil, nil, err`
function _M.register_rbac_resources(db, ws_name, ws_table)
  local bit   = require "bit"
  local rbac  = require "kong.rbac"
  local bxor  = bit.bxor

  local opts = ws_table and { workspace = ws_table.id }

  -- action int for all
  local action_bits_all = 0x0
  for k, v in pairs(rbac.actions_bitfields) do
    action_bits_all = bxor(action_bits_all, rbac.actions_bitfields[k])
  end

  local roles = {}
  local err, _
  -- now, create the roles and assign endpoint permissions to them

  -- first, a read-only role across everything
  roles.read_only, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "read-only",
    comment = "Read-only access across all initial RBAC resources",
  }, opts)

  if err then
    return nil, nil, err
  end

  -- this role only has the 'read-only' permissions
  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.read_only.id, },
    workspace = ws_name or "*",
    endpoint = "*",
    actions = rbac.actions_bitfields.read,
  })

  ws_name = ws_name or "default"

  if err then
    return nil, nil, err
  end

  -- admin role with CRUD access to all resources except RBAC resource
  roles.admin, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "admin",
    comment = "CRUD access to most initial resources (no RBAC)",
  }, opts)

  if err then
    return nil, nil, err
  end

  -- the 'admin' role has 'full-access' + 'no-rbac' permissions
  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.admin.id, },
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  local rbac_endpoints = { '/rbac/*', '/rbac/*/*', '/rbac/*/*/*', '/rbac/*/*/*/*', '/rbac/*/*/*/*/*', '/admins', '/admins/*' }
  for _, endpoint in ipairs(rbac_endpoints) do
    _, err = db.rbac_role_endpoints:insert({
      role = { id = roles.admin.id, },
      workspace = "*",
      endpoint = endpoint,
      negative = true,
      actions = action_bits_all, -- all actions
    })

    if err then
      return nil, nil, err
    end
  end

  -- finally, a super user role who has access to all initial resources
  roles.super_admin, err = db.rbac_roles:insert({
    id = utils.uuid(),
    name = "super-admin",
    comment = "Full CRUD access to all initial resources, including RBAC entities",
  }, opts)

  if err then
    return nil, nil, err
  end

  _, err = db.rbac_role_entities:insert({
    role = { id = roles.super_admin.id, },
    entity_id = "*",
    entity_type = "wildcard",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  _, err = db.rbac_role_endpoints:insert({
    role = { id = roles.super_admin.id, },
    workspace = "*",
    endpoint = "*",
    actions = action_bits_all, -- all actions
  })

  if err then
    return nil, nil, err
  end

  local super_admin, err = db.rbac_users:insert({
    id = utils.uuid(),
    name = "super_gruce-" .. ws_name,
    user_token = "letmein-" .. ws_name,
    enabled = true,
    comment = "Test - Initial RBAC Super Admin User"
  }, opts)

  if err then
    return nil, nil, err
  end

  local super_user_role, err = db.rbac_user_roles:insert({
    user = super_admin,
    role = roles.super_admin,
  })

  if err then
    return nil, nil, err
  end

  return super_admin, super_user_role
end


--- Returns the Dev Portal port.
-- Throws an error if not found in the configuration.
-- @tparam[opt=false] boolean ssl if `true` returns the ssl port
-- @treturn number the port
function _M.get_portal_api_port(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_api_listeners) do
    if entry.ssl == ssl then
      return entry.port
    end
  end
  error("No portal port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal ip.
-- Throws an error if not found in the configuration.
-- @tparam[opt=false] boolean ssl if `true` returns the ssl ip
-- @treturn string the ip address
function _M.get_portal_api_ip(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_api_listeners) do
    if entry.ssl == ssl then
      return entry.ip
    end
  end
  error("No portal ip found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal port.
-- Throws an error if not found in the configuration.
-- @tparam[opt=false] boolean ssl if `true` returns the ssl port
-- @treturn number the port
function _M.get_portal_gui_port(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_gui_listeners) do
    if entry.ssl == ssl then
      return entry.port
    end
  end
  error("No portal port found for ssl=" .. tostring(ssl), 2)
end


--- Returns the Dev Portal ip.
-- Throws an error if not found in the configuration.
-- @tparam[opt=false] boolean ssl if `true` returns the ssl ip
-- @treturn string the ip address
function _M.get_portal_gui_ip(ssl)
  if ssl == nil then ssl = false end
  for _, entry in ipairs(_M.portal_gui_listeners) do
    if entry.ssl == ssl then
      return entry.ip
    end
  end
  error("No portal ip found for ssl=" .. tostring(ssl), 2)
end


--- returns a pre-configured `http_client` for the Dev Portal API.
-- @tparam number timeout the timeout to use
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
function _M.portal_api_client(timeout)
  local portal_ip = _M.get_portal_api_ip()
  local portal_port = _M.get_portal_api_port()
  assert(portal_ip, "No portal_ip found in the configuration")
  return helpers.http_client(portal_ip, portal_port, timeout)
end


--- returns a pre-configured `http_client` for the Dev Portal GUI.
-- @tparam number timeout the timeout to use
-- the Kong configuration with this port
-- @return http-client, see `spec.helpers.http_client`.
function _M.portal_gui_client(timeout)
  local portal_ip = _M.get_portal_gui_ip()
  local portal_port = _M.get_portal_gui_port()
  assert(portal_ip, "No portal_ip found in the configuration")
  return helpers.http_client(portal_ip, portal_port, timeout)
end

-- TODO: remove this, the clients already have a post helper method...
function _M.post(client, path, body, headers, expected_status)
  headers = headers or {}
  headers["Content-Type"] = "application/json"
  local res = assert(client:send{
    method = "POST",
    path = path,
    body = body or {},
    headers = headers
  })
  return cjson.decode(assert.res_status(expected_status or 201, res))
end


--- Creates a new Admin user.
-- The returned admin will have the rbac token set in field `rbac_user.raw_user_token`. This
-- is only for test purposes and should never be done outside the test environment.
-- @param email email address
-- @param custom_id custom id to use
-- @param status admin status
-- @param db db object (see `spec.helper.get_db_utils`)
-- @param username username
-- @param workspace workspace
-- @return The admin object created, or `nil + err` on failure to get the token
-- @usage
-- local admin = eehelpers.create_admin(...)
-- local admin_token = admin.rbac_user.raw_user_token
function _M.create_admin(email, custom_id, status, db, username, workspace)
  local opts = workspace and { workspace = workspace.id }

  local admin = assert(db.admins:insert({
    username = username or email,
    custom_id = custom_id,
    email = email,
    status = status,
  }, opts))

  local token_res, err = admins_helpers.update_token(admin)
  if err then
    return nil, err
  end

  -- only used for tests so we can reference token
  -- WARNING: do not do this outside test environment
  admin.rbac_user.raw_user_token = token_res.body.token

  return admin
end

-- add a retry logic for CI
local function get_auth(client, username, password, retry)
  if not client then
    client = helpers.admin_client()
  end
  local res, err = assert(client:send {
    method = "GET",
    path = "/auth",
    headers = {
      ["Authorization"] = "Basic " .. ngx.encode_base64(username .. ":"
                                                        .. password),
      ["Kong-Admin-User"] = username,
    }
  })

  if err and err:find("closed", nil, true) and not retry then
    client = nil
    return get_auth(client, username, password, true)
  end
  assert.is_nil(err, "failed GET /auth: " .. tostring(err))
  assert.res_status(200, res)
  return res
end

--- returns the cookie for the admin.
-- @param client the http-client to use to make the auth request
-- @param username the admin user name to get the cookie for
-- @param password the password for the admin user
-- @return the cookie value, as returned in the `Set-Cookie` response header.
function _M.get_admin_cookie_basic_auth(client, username, password)
  local res = get_auth(client, username, password)
  return res.headers["Set-Cookie"]
end

--- Sets up the oauth introspection fixture.
-- This generates a fixture. The ip+port+path is used to generate the nginx directives
-- `listen` and `location` in the fixture/mock.
-- @tparam[opt] string ip the ip address, default `"127.0.0.1"`
-- @tparam[opt] number port the port, default `10000`
-- @tparam[opt] string path the path, default `"/introspect"`
-- @return fixture + url, where url is build from the input ip/port/path, and fixture is a table with an `http_mock` that
-- can be used when calling `spec.helpers.start_kong`.
function _M.setup_oauth_introspection_fixture(ip, port, path)
  path = path or "/introspect"
  ip = ip or "127.0.0.1"
  port =  port or "10000"

  local introspection_url = ("http://%s:%s%s"):format(
                            ip, port, path)
  local fixtures = {
    http_mock = {
      mock_introspection = [=[
        server {
            server_name mock_introspection;
            listen ]=] .. port .. [=[;
            location ~ "]=] .. path .. [=[" {
                content_by_lua_block {
                  local function x()

                    ngx.req.set_header("Content-Type", "application/json")

                    if ngx.req.get_method() == "POST" then
                      ngx.req.read_body()
                      local args = ngx.req.get_post_args()
                      if not args then
                        return ngx.exit(500)
                      end
                      if args.token == "valid" or
                        args.token == "valid_consumer_client_id" or
                        args.token == "valid_consumer_client_id_not_added_initially" or
                        args.token == "valid_consumer" or
                        args.token == "valid_consumer_limited" or
                        args.token == "valid_expired" or
                        args.token == "invalid_with_errors" or
                        args.token == "invalid_without_errors" or
                        args.token == "valid_complex" then

                        if args.token == "valid_consumer" then
                          ngx.say([[{"active":true,
                                    "username":"bob"}]])
                        elseif args.token == "valid_consumer_client_id" then -- omit `username`, return `client_id`
                          ngx.say([[{"active":true,
                                      "client_id": "kongsumer"}]])
                        elseif args.token == "valid_consumer_client_id_not_added_initially" then -- omit `username`, return `client_id`
                          ngx.say([[{"active":true,
                                      "client_id": "kongsumer_not_added_initially"}]])
                        elseif args.token == "valid_consumer_limited" then
                          ngx.say([[{"active":true,
                                    "username":"limited-bob"}]])
                        elseif args.token == "valid_complex" then
                          ngx.say([[{"active":true,
                                    "username":"some_username",
                                    "client_id":"some_client_id",
                                    "scope":"some_scope",
                                    "sub":"some_sub",
                                    "aud":"some_aud",
                                    "iss":"some_iss",
                                    "exp":"99999999999",
                                    "iat":"some_iat",
                                    "foo":"bar",
                                    "bar":"baz",
                                    "baz":"baaz"}]])
                        elseif args.token == "valid_expired" then
                          ngx.say([[{"active":true,
                                    "exp":"1"}]])
                        elseif args.token == "invalid_with_errors" then
                          ngx.say([[{"active":false, "error":"dummy error", "error_description": "dummy error desc"}]])
                        elseif args.token == "invalid_without_errors" then
                          ngx.say([[{"active":false}]])
                        else
                          ngx.say([[{"active":true}]])
                        end
                        return ngx.exit(200)
                      end
                    end

                    ngx.say([[{"active":false}]])
                    return ngx.exit(200)

                  end
                  local ok, err = pcall(x)
                  if not ok then
                    ngx.log(ngx.ERR, "Mock error: ", err)
                  end
                }
            }
        }
      ]=]
    },
  }
  return fixtures, introspection_url
end




do
  local resty_ws_client = require "resty.websocket.client"
  local ws = require "spec-ee.fixtures.websocket"
  local ws_const = require "spec-ee.fixtures.websocket.constants"
  local inspect = require "inspect"

  local function response_status(res)
    if type(res) ~= "string" then
      error("expected response data as a string", 2)
    end

    -- 123456789012345678901234567890
    -- 000000000111111111122222222223
    -- HTTP/1.1 301 Moved Permanently
    local version = tonumber(res:sub(6, 8))
    if not version then
      return nil, "failed parsing HTTP response version"
    end

    local status = tonumber(res:sub(10, 12))
    if not status then
      return nil, "failed parsing HTTP response status"
    end

    local reason = res:match("[^\r\n]+", 14)

    return status, version, reason
  end

  local headers_mt = {
    __index = function(self, k)
      return rawget(self, k:lower())
    end,

    __newindex = function(self, k, v)
      return rawset(self, k:lower(), v)
    end,
  }


  local function add_header(t, name, value)
    if not name or not value then
      return
    end

    if t[name] then
      value = { t[name], value }
    end
    t[name] = value
  end


  local function response_headers(res)
    if type(res) ~= "string" then
      return nil, "expected response data as a string"
    end

    local seen_status_line = false

    local headers = setmetatable({}, headers_mt)

    for line in res:gmatch("([^\r\n]+)") do
      if seen_status_line then
        local name, value = line:match([[^([^:]+):%s*(.+)]])

        add_header(headers, name, value)
      else
        seen_status_line = true
      end
    end

    return headers
  end

  -- format WebSocket request headers
  --
  -- This function accepts headers in both forms:
  --
  -- * hash-like: { name = "value" }
  -- * array-like: { "name: value" }
  --
  -- ...and formats them into { "name: value" } for lua-resty-websocket
  --
  local function format_request_headers(headers)
    if not headers then return end

    local t = {}

    for i = 1, #headers do
      t[i] = headers[i]
      headers[i] = nil
    end
    for k, v in pairs(headers) do
      if type(v) == "table" then
        for _, val in ipairs(v) do
          table.insert(t, k .. ": " .. val)
        end
      else
        table.insert(t, k .. ": " .. v)
      end
    end

    if #t == 0 then return end
    return t
  end

  local fmt = string.format

  local function handle_failure(params, uri, err, res, id)
    local msg = {
      "WebSocket handshake failed!",
      "--- Request URI: " .. uri,
      "--- Request Params:", inspect(params),
      "--- Error: ", err or "unknown error",
      "--- Response:", res or "<none>",
    }

    -- attempt to retrieve the request ID from the request or response headers
    local header = ws_const.headers.id
    id = id or
         params and
         params.headers and
         params.headers[header] or
         (response_headers(res) or {})[header]

    if id then
      table.insert(msg, "--- Request ID: " .. id)
      local log = ws.get_session_log(id)
      if log then
        table.insert(msg, "--- kong.log.serialize():")
        table.insert(msg, inspect(log))
      end
    end

    table.insert(msg, "---")
    assert(nil, table.concat(msg, "\n\n"))
  end


  -- param client ws.test.client
  local function body_reader(client)
    -- param res ws.test.client.response
    return function(res)
      if res._cached_body then
        return res._cached_body
      end

      local body = ""
      local err

      local status = res.original_status or res.status
      local content_length = tonumber(res.headers["content-length"])

      local sock = client.client.sock

      if status == 101 then
        -- simulate HTTP mock upstream
        body = client:get_raw_request()

      elseif content_length then
        sock:settimeout(1000)
        body, err = sock:receive(content_length)
        sock:close()

      else
        sock:close()
      end

      -- cache the result so :read_body() can be called multiple times
      res._cached_body = body or ""

      return body, err
    end
  end

  local OPCODES = ws_const.opcode

  -- param client resty.websocket.client
  -- param data string
  -- return boolean ok
  -- return string? error
  local function init_fragment(client, opcode, data)
    return client:send_frame(false, opcode, data)
  end

  -- param client resty.websocket.client
  -- param data string
  -- return boolean ok
  -- return string? error
  local function continue_fragment(client, data)
    return client:send_frame(false, OPCODES.continuation, data)
  end

  -- param client resty.websocket.client
  -- param data string
  -- return boolean ok
  -- return string? error
  local function finish_fragment(client, data)
    return client:send_frame(true, OPCODES.continuation, data)
  end

  -- param client resty.websocket.client
  -- param typ '"text"'|'"binary"'
  -- param data string[]
  -- return boolean ok
  -- return string? error
  local function send_fragments(client, typ, data)
    assert(typ == "text" or typ == "string",
           "attempt to fragment non-data frame")

    local opcode = OPCODES[typ]
    local ok, err
    local len = #data
    for i = 1, len do
      local first = i == 1
      local last = i == len

      local payload = data[i]

      -- single length: just send a single frame
      if first and last then
        ok, err = client:send_frame(true, opcode, payload)

      -- first frame: init fragment
      elseif first then
        ok, err = init_fragment(client, opcode, payload)

      -- last frame: finish fragment
      elseif last then
        ok, err = finish_fragment(client, payload)

      -- in the middle: continue
      else
        ok, err = continue_fragment(client, payload)
      end

      if not ok then
        return nil, fmt("failed sending %s fragment %s/%s: %s",
                        typ, i, len, err)
      end
    end

    return true
  end

  -- @class ws.test.client.response : table
  -- @field status number
  -- @field reason string
  -- @field version number
  -- @field headers table<string, string|string[]>
  -- @field read_body function

  -- @class ws.test.client
  -- @field client resty.websocket.client
  -- @field id string
  -- @field response ws.test.client.response
  local ws_client = {}

  -- param data string|string[]
  -- return boolean ok
  -- return string? error
  function ws_client:send_text(data)
    if type(data) == "table" then
      return send_fragments(self.client, "text", data)
    end

    return self.client:send_text(data)
  end

  -- param data string|string[]
  -- return boolean ok
  -- return string? error
  function ws_client:send_binary(data)
    if type(data) == "table" then
      return send_fragments(self.client, "binary", data)
    end

    return self.client:send_binary(data)
  end

  -- param data string
  -- return boolean ok
  -- return string? error
  function ws_client:init_text_fragment(data)
    return init_fragment(self.client, OPCODES.text, data)
  end

  -- param data string
  -- return boolean ok
  -- return string? error
  function ws_client:init_binary_fragment(data)
    return init_fragment(self.client, OPCODES.binary, data)
  end

  -- param data string
  -- return boolean ok
  -- return string? error
  function ws_client:send_continue(data)
    return continue_fragment(self.client, data)
  end

  -- param data string
  -- return boolean ok
  -- return string? error
  function ws_client:send_final_fragment(data)
    return finish_fragment(self.client, data)
  end


  -- param data? string
  -- return boolean ok
  -- return string? error
  function ws_client:send_ping(data)
    return self.client:send_ping(data)
  end

  -- param data? string
  -- return boolean ok
  -- return string? error
  function ws_client:send_pong(data)
    return self.client:send_pong(data)
  end

  -- param data? string
  -- param status? integer
  -- return boolean ok
  -- return string? error
  function ws_client:send_close(data, status)
    return self.client:send_close(status, data)
  end

  function ws_client:send_frame(...)
    return self.client:send_frame(...)
  end

  -- return string? data
  -- return string? type
  -- return string|number|nil err
  function ws_client:recv_frame()
    return self.client:recv_frame()
  end

  -- unlike resty.websocket.client, this does _not_ attempt to send
  -- a close frame
  -- return boolean ok
  -- return string? error
  function ws_client:close()
    return self.client.sock:close()
  end

  -- fetch the raw handshake request data (as seen by the mock upstream)
  -- return string
  function ws_client:get_raw_request()
    if self._request then
      return self._request
    end

    local sent, err = self:send_text(ws_const.tokens.request)
    assert.truthy(sent, "failed sending $_REQUEST text frame: " .. tostring(err))

    local data, typ, status = self:recv_frame()
    assert.truthy(data, "failed receiving request data: " .. tostring(status))
    assert.equals("text", typ, "wrong message type for request: " .. typ)

    self._request = data
    return data
  end

  -- fetch and decode handshake request data (as seen by the mock upstream)
  -- return table
  function ws_client:get_request()
    local data = self:get_raw_request()
    local req = assert(cjson.decode(data))

    local headers = setmetatable({}, headers_mt)
    for k, v in pairs(req.headers) do
      headers[k] = v
    end
    req.headers = headers

    return req
  end

  ws_client.__index = ws_client


  --- Instantiate a WebSocket client
  -- @tparam table opts options table
  -- @tparam string opts.path the path
  -- @tparam table opts.query table with query args
  -- @tparam string opts.scheme either '"ws"'|'"wss"'
  -- @tparam number opts.port port
  -- @tparam string opts.addr address
  -- @tparam bool opts.fail_on_error boolean fail on error
  -- @tparam number opts.connect_timeout connect timeout
  -- @tparam number opts.write_timeout write timeout
  -- @tparam number opts.read_timeout read timeout
  -- @tparam number opts.timeout generic timeout if others not given
  -- @return websocket client
  function _M.ws_client(opts)
    opts = opts or {}

    local query = opts.query or {}
    local scheme = opts.scheme or "ws"

    local port = opts.port
    if not port then
      port = (scheme == "wss" and 443) or 80
    end

    local client, err = resty_ws_client:new({ max_payload_len = 2^31 })
    assert(client, err)

    local qs = ngx.encode_args(query)
    if qs and qs ~= "" then qs = "?" .. qs end

    local uri = fmt("%s://%s:%s%s%s",
      scheme,
      opts.addr or opts.host or "127.0.0.1",
      port,
      opts.path or "/",
      qs
    )

    if opts.connect_timeout or opts.write_timeout or opts.read_timeout then
      client.sock:settimeouts(opts.connect_timeout,
                              opts.write_timeout,
                              opts.read_timeout)
    elseif opts.timeout then
      client.sock:settimeout(opts.timeout)
    end

    local id = opts.headers and opts.headers[ws_const.headers.id]

    local params = {
      host            = opts.host or opts.addr or "127.0.0.1",
      origin          = opts.origin,
      key             = opts.key,
      server_name     = opts.server_name or opts.host or opts.addr,
      keep_response   = true,
      headers         = format_request_headers(opts.headers),
      client_cert     = opts.client_cert,
      client_priv_key = opts.client_priv_key,
    }

    local ok, res
    ok, err, res = client:connect(uri, params)

    if opts.fail_on_error and (not ok or err ~= nil) then
      handle_failure(params, uri, err, res, id)
    end

    assert.is_not_nil(res, "resty.websocket.client:connect() returned no response data")

    local status, version, reason = response_status(res)
    assert.not_nil(status, version)

    local self = setmetatable({
      client = client,
      response = {
        status = status,
        reason = reason,
        version = version,
        headers = response_headers(res),
      }
    }, ws_client)


    -- without this function the response modifier won't think this is
    -- a valid response object
    self.response.read_body = body_reader(self)

    self.id = id or self.response.headers[ws_const.headers.id]

    return self
  end

  --- Establish a WebSocket connection to Kong.
  -- The defaults take the `opts.scheme` into account and will automatically
  -- pick either the plain or ssl based details.
  -- @tparam table opts same table as `ws_client`, but has defaults for the following fields;
  -- @tparam number opts.port port, defaults to Kong proxy port
  -- @tparam string opts.addr address, defaults to Kong proxy ip
  -- @tparam bool opts.fail_on_error boolean fail on error, defaults to `true`
  -- @return websocket client
  function _M.ws_proxy_client(opts)
    opts = opts or {}
    local ssl = opts.scheme == "wss"

    if not opts.addr then
      opts.addr = helpers.get_proxy_ip(ssl)
    end

    if not opts.port then
      opts.port = helpers.get_proxy_port(ssl)
    end

    if opts.fail_on_error ~= false then
      opts.fail_on_error = true
    end

    return assert(_M.ws_client(opts))
  end


  -- A client object that is loosely compatible with `helpers.proxy_client`
  -- but is WebSocket-aware.
  --
  -- This is mostly useful for tests that need to validate request/response
  -- data (i.e. auth plugins) and is not intended for WebSocket-centric tests
  local ws_compat_client = {}

  function ws_compat_client:send(params)
    if params.method then
      assert.equals("GET", params.method, "only GET is supported")
      params.method = nil
    end

    do
      local host, host_key
      for k, v in pairs(params.headers or {}) do
        if k:lower() == "host" then
          host = v
          host_key = k
          break
        end
      end

      if host_key then
        params.headers[host_key] = nil
      end

      params.host = host
    end

    if not params.force_path then
      -- this saves me from having to update lots and lots of tests
      local path = params.path or "/"

      local qs = path:find("?", 1, true)
      if qs then
        params.query = ngx.decode_args( (path:sub(qs + 1)) )
        path = path:sub(1, qs - 1)
      end

      params.path = path
    end

    params.fail_on_error = false

    if self.ssl then
      params.ssl = true
    end

    local client = _M.ws_proxy_client(params)
    assert.not_nil(client)

    local response = client.response

    if response.status == 101 then
      assert.not_nil(response.headers[ws_const.headers.self],
                     ws.const.headers.self .. " header is missing. " ..
                     "The request was not routed to the proper route/service")
      client:get_request()
      client:send_close()
      client:close()

      -- many existing tests check for a 200 status code
      --
      -- monkey-patch it so that we don't have to update everything
      response.status = 200
      response.original_status = 101
    else

      -- read the body once (this ensures that the underlying socket is closed)
      local body, err = response:read_body()
      assert.not_nil(body, "failed reading non-101 websocket response body: ", err)
    end

    return client.response
  end

  function ws_compat_client:get(path, params)
    params.path = path
    params.method = "GET"
    return self:send(params)
  end

  function ws_compat_client:close()
    return true
  end

  setmetatable(ws_compat_client, {
    __index = function(_, k)
      error("method " .. tostring(k) .. " is NYI")
    end,
  })



  --- A client object that is loosely compatible with `spec.helpers.proxy_client`
  -- but is WebSocket-aware.
  --
  -- This is mostly useful for tests that need to validate request/response
  -- data (i.e. auth plugins) and is not intended for WebSocket-centric tests
  --
  -- See `spec-ee.helpers.each_protocol`
  function _M.ws_proxy_client_compat()
    return setmetatable({ ssl = false }, { __index = ws_compat_client })
  end

  --- A client for wss. Same as the WS one, but for WSS.
  -- See `spec-ee.helpers.ws_proxy_client_compat` and `spec-ee.helpers.each_protocol`.
  function _M.wss_proxy_client_compat()
    return setmetatable({ ssl = true }, { __index = ws_compat_client })
  end

end


do
  local protos = {
    http = {
      proxy_client = helpers.proxy_client,
      proxy_ssl_client = helpers.proxy_ssl_client,
      OK = 200,
      route_protos = { "http" },
      service_proto = "http",
      service_proto_tls = "https",
    },

    websocket = {
      proxy_client = _M.ws_proxy_client_compat,
      proxy_ssl_client = _M.wss_proxy_client_compat,
      OK = 101,
      route_protos = { "ws" },
      service_proto = "ws",
      service_proto_tls = "wss",
    },
  }

  --- Iterator over http and websocket protocols.
  -- This is useful to run the same tests over multiple protocols. The returned
  -- table has entries for each protocol specific element.
  --
  -- @usage
  -- -- check the 'proto' table for other fields supported
  -- for proto in eehelpers.each_protocol() do
  --
  --   describe("running tests for protocol '"..proto.service_proto.."'", function()
  --
  --     local client = proto.proxy_client() -- returns either an `http` or `ws` client
  --     local sslclient = proto.proxy_ssl_client() -- returns either an `https` or `wss` client
  --     local ok_status = proto.OK -- returns either 200 (for http) or 101 (for ws)
  --
  --     it("do a test", function()
  --       -- test here
  --     end)
  --   end)
  -- end
  function _M.each_protocol()
    return pairs(protos)
  end
end


-- This function clears the license envs, avoiding to break the tests
-- that use license data.
-- It returns a function to set the envs back.
function _M.clear_license_env()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    else
      helpers.unsetenv("KONG_LICENSE_DATA")
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    else
      helpers.unsetenv("KONG_LICENSE_PATH")
    end
  end
end


function _M.get_portal_and_vitals_key()
  local key, err = pl_file.read("spec-ee/fixtures/mock_portal_and_vitals_key.txt")

  if err then
    return nil, err
  end

  return key
end


----------------
-- Variables/constants
-- @section exported-fields


--- A list of fields/constants exported on the `spec-ee.helpers` module table:
-- @table helpers
-- @field portal_api_listeners the listener configuration for the Portal API
-- @field portal_gui_listeners the listener configuration for the Portal GUI
-- @field admin_gui_listeners the listener configuration for the Admin GUI
-- @field redis_cluster_addresses the contact points for the Redis Cluster

local http_flags = { "ssl", "http2", "proxy_protocol", "transparent" }
_M.portal_api_listeners = listeners._parse_listeners(helpers.test_conf.portal_api_listen, http_flags)
_M.portal_gui_listeners = listeners._parse_listeners(helpers.test_conf.portal_gui_listen, http_flags)
_M.admin_gui_listeners = listeners._parse_listeners(helpers.test_conf.admin_gui_listen, http_flags)
_M.redis_cluster_addresses = _M.parsed_redis_cluster_addresses()

return _M
