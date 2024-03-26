--- Module implementing http_mock, a HTTP mocking server for testing.
-- @module spec.helpers.http_mock

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

-- get a session from the logs with a timeout
-- throws error if no request is recieved within the timeout
-- @treturn table the session
function http_mock:get_session()
  local ret
  self.eventually:has_session_satisfy(function(s)
    ret = s
    return true
  end)
  return ret
end

-- get a request from the logs with a timeout
-- throws error if no request is recieved within the timeout
-- @treturn table the request
function http_mock:get_request()
  return self:get_session().req
end

-- get a response from the logs with a timeout
-- throws error if no request is recieved within the timeout
-- @treturn table the response
function http_mock:get_response()
  return self:get_session().resp
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

--- create a mock instance which represents a HTTP mocking server
-- @tparam[opt] table|string|number listens the listen directive of the mock server. This can be
-- a single directive (string), or a list of directives (table), or a number which will be used as the port.
-- Defaults to a random available port
-- @tparam[opt] table|string routes the code of the mock server, defaults to a simple response. See Examples.
-- @tparam[opt={}] table opts options for the mock server, supporting fields:
-- @tparam[opt="servroot_tapping"] string opts.prefix the prefix of the mock server
-- @tparam[opt="_"] string opts.hostname the hostname of the mock server
-- @tparam[opt=false] bool opts.tls whether to use tls
-- @tparam[opt={}] table opts.directives the extra directives of the mock server
-- @tparam[opt={}] table opts.log_opts the options for logging with fields listed below:
-- @tparam[opt=true] bool opts.log_opts.collect_req whether to log requests()
-- @tparam[opt=true] bool opts.log_opts.collect_req_body_large whether to log large request bodies
-- @tparam[opt=false] bool opts.log_opts.collect_resp whether to log responses
-- @tparam[opt=false] bool opts.log_opts.collect_resp_body whether to log response bodies
-- @tparam[opt=true] bool opts.log_opts.collect_err: whether to log errors
-- @tparam[opt] string opts.init: the lua code injected into the init_by_lua_block
-- @treturn http_mock a mock instance
-- @treturn string the port the mock server listens to
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
--
-- -- or single a string, which will be used as the access phase handler.
-- routes = [[ ngx.print("hello world") ]]
-- -- which is equivalent to:
-- routes = {
--   ["/"] = {
--     access = [[ ngx.print("hello world") ]],
--   },
-- }
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

  local prefix = opts.prefix or "servroot_mock"
  local hostname = opts.hostname or "_"
  local directives = opts.directives or {}

  local _self = setmetatable({
    prefix = prefix,
    hostname = hostname,
    listens = listens,
    routes = routes,
    directives = directives,
    dicts = opts.dicts,
    init = opts.init,
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
  return _self, port
end

--- @type http_mock

--- returns the default port of the mock server.
-- @function http_mock:get_default_port
-- @treturn string the port of the mock server (from the first listen directive)
function http_mock:get_default_port()
  return self.listens[1]:match(":(%d+)")
end

--- retrieve the logs of HTTP sessions
-- @function http_mock:retrieve_mocking_logs
-- @treturn table the logs of HTTP sessions

--- purge the logs of HTTP sessions
-- @function http_mock:purge_mocking_logs

--- clean the logs of HTTP sessions
-- @function http_mock:clean

--- wait until all the requests are finished
-- @function http_mock:wait_until_no_request
-- @tparam[opt=true,default=5] number timeout the timeout to wait for the nginx process to exit

--- make assertions on HTTP requests.
-- with a timeout to wait for the requests to arrive
-- @table http_mock.eventually

--- assert if the condition is true for one of the logs.
--- Replace "session" in the name of the function to assert on fields of the log.
--- The field can be one of "session", "request", "response", "error".
-- @function http_mock.eventually:has_session_satisfy
-- @tparam function check the check function, accept a log and throw error if the condition is not satisfied

--- assert if the condition is true for all the logs.
-- Replace "session" in the name of the function to assert on fields of the log.
-- The field can be one of "session", "request", "response", "error".
-- @function http_mock.eventually:all_session_satisfy
-- @tparam function check the check function, accept a log and throw error if the condition is not satisfied

--- assert if none of the logs satisfy the condition.
-- Replace "session" in the name of the function to assert on fields of the log.
-- The field can be one of "session", "request", "response", "error".
-- @function http_mock.eventually:has_no_session_satisfy
-- @tparam function check the check function, accept a log and throw error if the condition is not satisfied

--- assert if not all the logs satisfy the condition.
-- Replace "session" in the name of the function to assert on fields of the log.
-- The field can be one of "session", "request", "response", "error".
-- @function http_mock.eventually:not_all_session_satisfy
-- @tparam function check the check function, accept a log and throw error if the condition is not satisfied

--- alias for eventually:not_all_{session,request,response,error}_satisfy.
-- Replace "session" in the name of the function to assert on fields of the log.
-- The field can be one of "session", "request", "response", "error".
-- @function http_mock.eventually:has_one_without_session_satisfy
-- @tparam function check the check function, accept a log and throw error if the condition is not satisfied

return http_mock
