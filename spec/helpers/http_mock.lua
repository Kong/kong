-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"

local pairs = pairs
local ipairs = ipairs
local type = type
local setmetatable = setmetatable

local modules = {
  require "spec.helpers.http_mock.nginx_instance",
  require "spec.helpers.http_mock.asserts",
  require "spec.helpers.http_mock.debug_port",
  require "spec.helpers.http_mock.clients",
}

local http_mock = {}

-- since http_mock contains a lot of functionality, it is implemented in separate submodules
-- and combined into one large http_mock module here.
for _, module in ipairs(modules) do
  for k, v in pairs(module) do
    http_mock[k] = v
  end
end

local http_mock_MT = { __index = http_mock, __gc = http_mock.stop }


-- TODO: make default_mocking the same to the `mock_upstream`
local default_mocking = {
  ["/"] = {
    access = [[
      ngx.req.set_header("X-Test", "test")
      ngx.print("ok")
      ngx.exit(200)
    ]],
  },
}

local function default_field(tbl, key, default)
  if tbl[key] == nil then
    tbl[key] = default
  end
end

-- create a mock instance which represents a HTTP mocking server
-- @param listens: the listen directive of the mock server, defaults to "0.0.0.0:8000"
-- @param code: the code of the mock server, defaults to a simple response.
-- @param opts: options for the mock server, left it empty to use the defaults
-- @return: a mock instance
-- @usage
-- local mock = http_mock.new(8000, [[
--   ngx.req.set_header("X-Test", "test")
--   ngx.print("hello world")
-- ]],  {
--   prefix = "mockserver",
--   log_opts = {
--     resp = true,
--     resp_body = true,
--   },
--   tls = true,
-- })
--
-- mock:start()
-- local client = mock:get_client() -- get a client to access the mocking port
-- local res = assert(client:send({}))
-- assert.response(res).has.status(200)
-- assert.response(res).has.header("X-Test", "test")
-- assert.response(res).has.body("hello world")
-- mock.eventually:has_response(function(resp)
--   assert.same(resp.body, "hello world")
-- end)
-- mock:wait_until_no_request() -- wait until all the requests are finished
-- mock:clean() -- clean the logs
-- client:send({})
-- client:send({})
-- local logs = mock:retrieve_mocking_logs() -- get all the logs of HTTP sessions
-- mock:stop()
--
-- listens can be a number, which will be used as the port of the mock server;
-- or a string, which will be used as the param of listen directive of the mock server;
-- or a table represents multiple listen ports.
-- if the port is not specified, a random port will be used.
-- call mock:get_default_port() to get the first port the mock server listens to.
-- if the port is a number and opts.tls is set to ture, ssl will be appended.
--
-- routes can be a table like this:
-- routes = {
--   ["/"] = {
--     access = [[
--       ngx.req.set_header("X-Test", "test")
--       ngx.print("hello world")
--     ]],
--     log = [[
--       ngx.log(ngx.ERR, "log test!")
--     ]],
--     directives = {
--       "rewrite ^/foo /bar break;",
--     },
--   },
-- }
-- or a string, which will be used as the access phase handler.
--
-- opts:
-- prefix: the prefix of the mock server, defaults to "mockserver"
-- hostname: the hostname of the mock server, defaults to "_"
-- directives: the extra directives of the mock server, defaults to {}
-- log_opts: the options for logging with fields listed below:
--   collect_req: whether to log requests(), defaults to true
--   collect_req_body_large: whether to log large request bodies, defaults to true
--   collect_resp: whether to log responses, defaults to false
--   collect_resp_body: whether to log response bodies, defaults to false
--   collect_err: whether to log errors, defaults to true
-- tls: whether to use tls, defaults to false
function http_mock.new(listens, routes, opts)
  opts = opts or {}

  if listens == nil then
    listens = helpers.get_available_port()
  end

  if type(listens) == "number" then
    listens = "0.0.0.0:" .. listens .. (opts.tls and " ssl" or "")
  end

  if type(listens) == "string" then
    listens = { listens, }
  end

  if routes == nil then
    routes = default_mocking
  elseif type(routes) == "string" then
    routes = {
      ["/"] = {
        access = routes,
      }
    }
  end

  opts.log_opts = opts.log_opts or {}
  local log_opts = opts.log_opts
  default_field(log_opts, "req", true)
  default_field(log_opts, "req_body_large", true)
  -- usually we can check response from client side
  default_field(log_opts, "resp", false)
  default_field(log_opts, "resp_body", false)
  default_field(log_opts, "err", true)

  local prefix = opts.prefix or "mockserver"
  local hostname = opts.hostname or "_"
  local directives = opts.directives or {}

  local _self = setmetatable({
    prefix = prefix,
    hostname = hostname,
    listens = listens,
    routes = routes,
    directives = directives,
    log_opts = log_opts,
    logs = {},
    tls = opts.tls,
    eventually_timeout = opts.eventually_timeout or 5,
  }, http_mock_MT)

  local port = _self:get_default_port()

  if port then
    _self.client_opts = {
      port = port,
      tls = opts.tls,
    }
  end

  _self:_set_eventually_table()
  _self:_setup_debug()
  return _self
end

function http_mock:get_default_port()
  return self.listens[1]:match(":(%d+)")
end

return http_mock