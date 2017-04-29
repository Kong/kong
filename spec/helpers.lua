------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2017 Mashape Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers

local BIN_PATH = "bin/kong"
local TEST_CONF_PATH = "spec/kong_tests.conf"
local CUSTOM_PLUGIN_PATH = "./spec/fixtures/custom_plugins/?.lua"

local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local cjson = require "cjson.safe"
local http = require "resty.http"
local log = require "kong.cmd.utils.log"

log.set_lvl(log.levels.quiet) -- disable stdout logs in tests

-- Add to package path so dao helpers can insert custom plugins
-- (while running from the busted environment)
package.path = CUSTOM_PLUGIN_PATH .. ";" .. package.path

---------------
-- Conf and DAO
---------------
local conf = assert(conf_loader(TEST_CONF_PATH))
local dao = assert(DAOFactory.new(conf))
-- make sure migrations are up-to-date
assert(dao:run_migrations())

-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = {}

local pack = function(...) return { n = select("#", ...), ... } end
local unpack = function(t) return unpack(t, 1, t.n) end

--- Prints all returned parameters.
-- Simple debugging aid.
-- @usage -- modify
-- local a,b = some_func(c,d)
-- -- into
-- local a,b = intercept(some_func(c,d))
local function intercept(...)
  local args = pack(...)
  print(require("pl.pretty").write(args))
  return unpack(args)
end

-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
end

--- Waits until a specific condition is met.
-- The check function will repeatedly be called (with a fixed interval), until
-- the condition is met, or the
-- timeout value is exceeded.
-- @param f check function that should return `thruthy` when the condition has
-- been met
-- @param timeout maximum time to wait after which an error is thrown
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
-- @usage -- wait 10 seconds for a file "myfilename" to appear
-- helpers.wait_until(function() return file_exist("myfilename") end, 10)
local function wait_until(f, timeout)
  if type(f) ~= "function" then
    error("arg #1 must be a function", 2)
  end

  timeout = timeout or 2
  local tstart = ngx.time()
  local texp = tstart + timeout
  local ok, res, err

  repeat
    ngx.sleep(0.2)
    ok, res, err = pcall(f)
  until not ok or res or ngx.time() >= texp

  if not ok then
    -- report error from `f`, such as assert gone wrong
    error(tostring(res), 2)
  elseif not res and err then
    -- report a failure for `f` to meet its condition
    -- and eventually an error return value which could be the cause
    error("wait_until() timeout: "..tostring(err).." (after delay: "..timeout.."s)", 2)
  elseif not res then
    -- report a failure for `f` to meet its condition
    error("wait_until() timeout (after delay "..timeout.."s)", 2)
  end
end

--- http_client.
-- An http-client class to perform requests.
-- @section http_client

--- Send a http request. Based on https://github.com/pintsized/lua-resty-http.
-- If `opts.body` is a table and "Content-Type" header contains
-- `application/json`, `www-form-urlencoded`, or `multipart/form-data`, then it
-- will automatically encode the body according to the content type.
-- If `opts.query` is a table, a query string will be constructed from it and
-- appended
-- to the request path (assuming none is already present).
-- @name http_client:send
-- @param opts table with options. See https://github.com/pintsized/lua-resty-http
function resty_http_proxy_mt:send(opts)
  local cjson = require "cjson"
  local utils = require "kong.tools.utils"

  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type, content_type_name = lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(opts.body) == "table"
  if string.find(content_type, "application/json") and t_body_table then
    opts.body = cjson.encode(opts.body)
  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = utils.encode_args(opts.body, true) -- true: not % encoded
  elseif string.find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = opts.body
    local boundary = "8fd84e9444e3946c"
    local body = ""

    for k, v in pairs(form) do
      body = body.."--"..boundary.."\r\nContent-Disposition: form-data; name=\""..k.."\"\r\n\r\n"..tostring(v).."\r\n"
    end

    if body ~= "" then
      body = body.."--"..boundary.."--\r\n"
    end

    local clength = lookup(headers, "content-length")
    if not clength then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type.."; boundary="..boundary
    end

    opts.body = body
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = utils.encode_args(opts.query)
    opts.path = opts.path.."?"..qs
    opts.query = nil
  end

  local res, err = self:request(opts)
  if res then
    -- wrap the read_body() so it caches the result and can be called multiple
    -- times
    local reader = res.read_body
    res.read_body = function(self)
      if (not self._cached_body) and (not self._cached_error) then
        self._cached_body, self._cached_error = reader(self)
      end
      return self._cached_body, self._cached_error
    end
  end

  return res, err
end

function resty_http_proxy_mt:__index(k)
  local f = rawget(resty_http_proxy_mt, k)
  if f then
    return f
  end

  return self.client[k]
end


--- Creates a http client. Based on https://github.com/pintsized/lua-resty-http
-- @name http_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param timeout in seconds
-- @return http client
-- @see http_client:send
local function http_client(host, port, timeout)
  timeout = timeout or 10000
  local client = assert(http.new())
  assert(client:connect(host, port))
  client:set_timeout(timeout)
  return setmetatable({
    client = client
  }, resty_http_proxy_mt)
end

--- returns a pre-configured `http_client` for the Kong proxy port.
-- @name proxy_client
local function proxy_client(timeout)
  return http_client(conf.proxy_ip, conf.proxy_port, timeout)
end

--- returns a pre-configured `http_client` for the Kong SSL proxy port.
-- @name proxy_ssl_client
local function proxy_ssl_client(timeout)
  local client = http_client(conf.proxy_ip, conf.proxy_ssl_port, timeout)
  assert(client:ssl_handshake())
  return client
end

--- returns a pre-configured `http_client` for the Kong admin port.
-- @name admin_client
local function admin_client(timeout)
  return http_client(conf.admin_ip, conf.admin_port, timeout)
end

---
-- TCP/UDP server helpers
--
-- @section servers

--- Starts a TCP server.
-- Accepts a single connection and then closes, echoing what was received
-- (single read).
-- @name tcp_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function tcp_server(port, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      server:settimeout(10)
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = assert(server:accept())
      local line = assert(client:receive())
      client:send(line .. "\n")
      client:close()
      server:close()
      return line
    end
  }, port)

  return thread:start(...)
end

--- Starts a HTTP server.
-- Accepts a single connection and then closes. Sends a 200 ok, 'Connection:
-- close' response.
-- If the request received has path `/delay` then the response will be delayed
-- by 2 seconds.
-- @name http_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function http_server(port, ...)
  local threads = require "llthreads2.ex"
  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", port))
      assert(server:listen())
      local client = assert(server:accept())

      local lines = {}
      local line, err
      while #lines < 7 do
        line, err = client:receive()
        if err then
          break
        else
          table.insert(lines, line)
        end
      end

      if #lines > 0 and lines[1] == "GET /delay HTTP/1.0" then
        ngx.sleep(2)
      end

      if err then
        server:close()
        error(err)
      end

      client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
      client:close()
      server:close()
      return lines
    end
  }, port)

  return thread:start(...)
end

--- Starts a UDP server.
-- Accepts a single connection, reading once and then closes
-- @name udp_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function udp_server(port)
  local threads = require "llthreads2.ex"

  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.udp())
      server:settimeout(5)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", port)
      local data, err = server:receive()
      server:close()
      return data, err
    end
  }, port or 9999)

  thread:start()

  ngx.sleep(0.1)

  return thread
end

--------------------
-- Custom assertions
--
-- @section assertions

local say = require "say"
local luassert = require "luassert.assert"

--- Generic modifier "response".
-- Will set a "response" value in the assertion state, so following
-- assertions will operate on the value set.
-- @name response
-- @param response results from `http_client:send` function.
-- @usage
-- local res = assert(client:send { ..your request parameters here ..})
-- local length = assert.response(res).has.header("Content-Length")
local function modifier_response(state, arguments, level)
  assert(arguments.n > 0,
        "response modifier requires a response object as argument")

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "response modifier requires a response object as argument, got: "..tostring(res))

  rawset(state, "kong_response", res)
  rawset(state, "kong_request", nil)

  return state
end
luassert:register("modifier", "response", modifier_response)

--- Generic modifier "request".
-- Will set a "request" value in the assertion state, so following
-- assertions will operate on the value set.
-- The request must be inside a 'response' from mockbin.org or httpbin.org
-- @name request
-- @param response results from `http_client:send` function. The request will
-- be extracted from the response.
-- @usage
-- local res = assert(client:send { ..your request parameters here ..})
-- local length = assert.request(res).has.header("Content-Length")
local function modifier_request(state, arguments, level)
  local generic = "The assertion 'request' modifier takes a http response"
                .." object as input to decode the json-body returned by"
                .." httpbin.org/mockbin.org, to retrieve the proxied request."

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http response object, got '"..tostring(res).."'. "..generic)

  local body, err
  body = assert(res:read_body())
  body, err = cjson.decode(body)

  assert(body, "Expected the http response object to have a json encoded body,"
             .." but decoding gave error '"..tostring(err).."'. "..generic)

  -- check if it is a mockbin request
  if lookup((res.headers or {}),"X-Powered-By") ~= "mockbin" then
    -- not mockbin, so httpbin?
    assert(type(body.url) == "string" and body.url:find("//httpbin.org", 1, true),
           "Could not determine the response to be from either mockbin.com or httpbin.org")
  end

  rawset(state, "kong_request", body)
  rawset(state, "kong_response", nil)

  return state
end
luassert:register("modifier", "request", modifier_request)

--- Generic fail assertion. A convenience function for debugging tests, always
-- fails. It will output the values it was called with as a table, with an `n`
-- field to indicate the number of arguments received.
-- @name fail
-- @param ... any set of parameters to be displayed with the failure
-- @usage
-- assert.fail(some, value)
local function fail(state, args)
  local out = {}
  for k,v in pairs(args) do out[k] = v end
  args[1] = out
  args.n = 1
  return false
end
say:set("assertion.fail.negative", [[
Fail assertion was called with the following parameters (formatted as a table);
%s
]])
luassert:register("assertion", "fail", fail,
                  "assertion.fail.negative",
                  "assertion.fail.negative")

--- Assertion to check whether a value lives in an array.
-- @name contains
-- @param expected The value to search for
-- @param array The array to search for the value
-- @param pattern (optional) If thruthy, then `expected` is matched as a string
-- pattern
-- @return the index at which the value was found
-- @usage
-- local arr = { "one", "three" }
-- local i = assert.contains("one", arr)        --> passes; i == 1
-- local i = assert.contains("two", arr)        --> fails
-- local i = assert.contains("ee$", arr, true)  --> passes; i == 2
local function contains(state, args)
  local expected, arr, pattern = unpack(args)
  local found
  for i = 1, #arr do
    if (pattern and string.match(arr[i], expected)) or (arr[i] == expected) then
      found = i
      break
    end
  end
  return found ~= nil, {found}
end
say:set("assertion.contains.negative", [[
Expected array to contain element.
Expected to contain:
%s
]])
say:set("assertion.contains.positive", [[
Expected array to not contain element.
Expected to not contain:
%s
]])
luassert:register("assertion", "contains", contains,
                  "assertion.contains.negative",
                  "assertion.contains.positive")

--- Assertion to check the statuscode of a http response.
-- @name status
-- @param expected the expected status code
-- @param response (optional) results from `http_client:send` function,
-- alternatively use `response`.
-- @return the response body as a string
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local body = assert.has.status(200, res)             -- or alternativly
-- local body = assert.response(res).has.status(200)    -- does the same
local function res_status(state, args)
  assert(not rawget(state, "kong_request"),
         "Cannot check statuscode against a request object,"
       .." only against a response object")

  local expected = args[1]
  local res = args[2] or rawget(state, "kong_response")

  assert(type(expected) == "number",
         "Expected response code must be a number value. Got: "..tostring(expected))
  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http_client response. Got: "..tostring(res))

  if expected ~= res.status then
    local body, err = res:read_body()
    if not body then body = "Error reading body: "..err end
    table.insert(args, 1, pl_stringx.strip(body))
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3

    if res.status == 500 then
      -- on HTTP 500, we can try to read the server's error logs
      -- for debugging purposes (very useful for travis)
      local str = pl_file.read(conf.nginx_err_logs)
      if not str then
        return false -- no err logs to read in this prefix
      end

      local str_t = pl_stringx.splitlines(str)
      local first_line = #str_t - math.min(60, #str_t) + 1
      local msg_t = {"\nError logs ("..conf.nginx_err_logs.."):"}
      for i = first_line, #str_t do
        msg_t[#msg_t+1] = str_t[i]
      end

      table.insert(args, 4, table.concat(msg_t, "\n"))
      args.n = 4
    end

    return false
  else
    local body, err = res:read_body()
    local output = body
    if not output then output = "Error reading body: "..err end
    output = pl_stringx.strip(output)
    table.insert(args, 1, output)
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3
    return true, {pl_stringx.strip(body)}
  end
end
say:set("assertion.res_status.negative", [[
Invalid response status code.
Status expected:
%s
Status received:
%s
Body:
%s
%s]])
say:set("assertion.res_status.positive", [[
Invalid response status code.
Status not expected:
%s
Status received:
%s
Body:
%s
%s]])
luassert:register("assertion", "status", res_status,
                  "assertion.res_status.negative", "assertion.res_status.positive")
luassert:register("assertion", "res_status", res_status,
                  "assertion.res_status.negative", "assertion.res_status.positive")

--- Checks and returns a json body of an http response/request. Only checks
-- validity of the json, does not check appropriate headers. Setting the target
-- to check can be done through `request` or `response` (requests are only
-- supported with mockbin.com).
-- @name jsonbody
-- @return the decoded json as a table
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local json_table = assert.response(res).has.jsonbody()
local function jsonbody(state, args)
  assert(args[1] == nil and rawget(state, "kong_request") or rawget(state, "kong_response"),
         "the `jsonbody` assertion does not take parameters. "..
         "Use the `response`/`require` modifiers to set the target to operate on")

  if rawget(state, "kong_response") then
    local body = rawget(state, "kong_response"):read_body()
    local json, err = cjson.decode(body)
    if not json then
      table.insert(args, 1, "Error decoding: "..tostring(err).."\nResponse body:"..body)
      args.n = 1
      return false
    end
    return true, {json}
  else
    assert(rawget(state, "kong_request").postData, "No post data found in the request. Only mockbin.com is supported!")
    local json, err = cjson.decode(rawget(state, "kong_request").postData.text)
    if not json then
      table.insert(args, 1, "Error decoding: "..tostring(err).."\nRequest body:"..rawget(state, "kong_request").postData.text)
      args.n = 1
      return false
    end
    return true, {json}
  end
end
say:set("assertion.jsonbody.negative", [[
Expected response body to contain valid json. Got:
%s
]])
say:set("assertion.jsonbody.positive", [[
Expected response body to not contain valid json. Got:
%s
]])
luassert:register("assertion", "jsonbody", jsonbody,
                  "assertion.jsonbody.negative",
                  "assertion.jsonbody.positive")

--- Adds an assertion to look for a named header in a `headers` subtable.
-- Header name comparison is done case-insensitive.
-- @name header
-- @param name header name to look for (case insensitive).
-- @see response
-- @see request
-- @return value of the header
local function res_header(state, args)
  local header = args[1]
  local res = args[2] or rawget(state, "kong_request") or rawget(state, "kong_response")
  assert(type(res) == "table" and type(res.headers) == "table",
         "'header' assertion input does not contain a 'headers' subtable")
  local value = lookup(res.headers, header)
  table.insert(args, 1, res.headers)
  table.insert(args, 1, header)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.res_header.negative", [[
Expected header:
%s
But it was not found in:
%s
]])
say:set("assertion.res_header.positive", [[
Did not expected header:
%s
But it was found in:
%s
]])
luassert:register("assertion", "header", res_header,
                  "assertion.res_header.negative",
                  "assertion.res_header.positive")

---
-- An assertion to look for a query parameter in a `queryString` subtable.
-- Parameter name comparison is done case-insensitive.
-- @name queryparam
-- @param name name of the query parameter to look up (case insensitive)
-- @return value of the parameter
local function req_query_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'queryparam' assertion only works with a request object")
  local params
  if type(req.queryString) == "table" then
    -- it's a mockbin one
    params = req.queryString
  elseif type(req.args) == "table" then
    -- it's a httpbin one
    params = req.args
  else
    error("No query parameters found in request object")
  end
  local value = lookup(params, param)
  table.insert(args, 1, params)
  table.insert(args, 1, param)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.req_query_param.negative", [[
Expected query parameter:
%s
But it was not found in:
%s
]])
say:set("assertion.req_query_param.positive", [[
Did not expected query parameter:
%s
But it was found in:
%s
]])
luassert:register("assertion", "queryparam", req_query_param,
                  "assertion.req_query_param.negative",
                  "assertion.req_query_param.positive")

---
-- Adds an assertion to look for a urlencoded form parameter in a mockbin request.
-- Parameter name comparison is done case-insensitive. Use the `request` modifier to set
-- the request to operate on.
-- @name formparam
-- @param name name of the form parameter to look up (case insensitive)
-- @return value of the parameter
local function req_form_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'formparam' assertion can only be used with a mockbin/httpbin request object")

  local value
  if req.postData then
    -- mockbin request
    value = lookup((req.postData or {}).params, param)
  elseif (type(req.url) == "string") and (req.url:find("//httpbin.org", 1, true)) then
    -- hhtpbin request
    value = lookup(req.form or {}, param)
  else
    error("Could not determine the request to be from either mockbin.com or httpbin.org")
  end
  table.insert(args, 1, req)
  table.insert(args, 1, param)
  args.n = 2
  if not value then
    return false
  end
  return true, {value}
end
say:set("assertion.req_form_param.negative", [[
Expected url encoded form parameter:
%s
But it was not found in request:
%s
]])
say:set("assertion.req_form_param.positive", [[
Did not expected url encoded form parameter:
%s
But it was found in request:
%s
]])
luassert:register("assertion", "formparam", req_form_param,
                  "assertion.req_form_param.negative",
                  "assertion.req_form_param.positive")

----------------
-- Shell helpers
-- @section Shell-helpers

--- Execute a command.
-- Modified version of `pl.utils.executeex()` so the output can directly be
-- used on an assertion.
-- @name execute
-- @param ... see penlight documentation
-- @return ok, stderr, stdout; stdout is only included when the result was ok
local function exec(...)
  local ok, _, stdout, stderr = pl_utils.executeex(...)
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end

--- Execute a Kong command.
-- @name kong_exec
-- @param cmd Kong command to execute, eg. `start`, `stop`, etc.
-- @param env (optional) table with kong parameters to set as environment
-- variables, overriding the test config (each key will automatically be
-- prefixed with `KONG_` and be converted to uppercase)
-- @return same output as `exec`
local function kong_exec(cmd, env)
  cmd = cmd or ""
  env = env or {}

  -- Insert the Lua path to the custom-plugin fixtures
  if not env.lua_package_path then
    env.lua_package_path = CUSTOM_PLUGIN_PATH

  else
    env.lua_package_path = CUSTOM_PLUGIN_PATH .. ";" .. env.lua_package_path
  end

  env.lua_package_path = env.lua_package_path .. ";" .. conf.lua_package_path

  -- build Kong environment variables
  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s='%s'", env_vars, k:upper(), v)
  end

  return exec(env_vars.." "..BIN_PATH.." "..cmd)
end

--- Prepare the Kong environment.
-- creates the workdirectory and deletes any existing one.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @name prepare_prefix
local function prepare_prefix(prefix)
  prefix = prefix or conf.prefix
  exec("rm -rf "..prefix.."/*")
  return pl_dir.makepath(prefix)
end

--- Cleans the Kong environment.
-- Deletes the working directory if it exists.
-- @param prefix (optional) path to the working directory, if omitted the test
-- configuration will be used
-- @name clean_prefix
local function clean_prefix(prefix)
  prefix = prefix or conf.prefix
  if pl_path.exists(prefix) then
    pl_dir.rmtree(prefix)
  end
end

--- Waits for invalidation of a cached key by polling the mgt-api
-- and waiting for a 404 response.
-- @name wait_for_invalidation
-- @param key the cache-key to check
-- @param timeout (optional) in seconds, defaults to 10.
local function wait_for_invalidation(key, timeout)
  local api_client = admin_client()
  timeout = timeout or 10
  wait_until(function()
    local res = assert(api_client:send {
      method = "GET",
      path = "/cache/"..key,
      headers = {}
    })
    res:read_body()
    return res.status == 404
  end, timeout)
end

----------
-- Exposed
----------
-- @export
return {
  -- Penlight
  dir = pl_dir,
  path = pl_path,
  file = pl_file,
  utils = pl_utils,

  -- Kong testing properties
  dao = dao,
  bin_path = BIN_PATH,
  test_conf = conf,
  test_conf_path = TEST_CONF_PATH,

  -- Kong testing helpers
  execute = exec,
  kong_exec = kong_exec,
  http_client = http_client,
  wait_until = wait_until,
  tcp_server = tcp_server,
  udp_server = udp_server,
  http_server = http_server,
  proxy_client = proxy_client,
  admin_client = admin_client,
  proxy_ssl_client = proxy_ssl_client,
  prepare_prefix = prepare_prefix,
  clean_prefix = clean_prefix,
  wait_for_invalidation = wait_for_invalidation,
  
  -- miscellaneous
  intercept = intercept,

  start_kong = function(env)
    env = env or {}
    local ok, err = prepare_prefix(env.prefix)
    if not ok then return nil, err end

    local nginx_conf = ""
    if env.nginx_conf then
      nginx_conf = " --nginx-conf " .. env.nginx_conf
    end

    return kong_exec("start --conf " .. TEST_CONF_PATH .. nginx_conf, env)
  end,
  stop_kong = function(prefix, preserve_prefix)
    prefix = prefix or conf.prefix
    local ok, err = kong_exec("stop --prefix "..prefix)
    dao:truncate_tables()
    if not preserve_prefix then
      clean_prefix(prefix)
    end
    return ok, err
  end,
  -- Only use in CLI tests from spec/02-integration/01-cmd
  kill_all = function(prefix)
    local kill = require "kong.cmd.utils.kill"

    dao:truncate_tables()

    local default_conf = conf_loader(nil, {prefix = prefix or conf.prefix})
    local running_conf = conf_loader(default_conf.kong_env)
    if not running_conf then return end

    -- kill kong_tests.conf services
    for _, pid_path in ipairs {running_conf.nginx_pid,
                               running_conf.serf_pid} do
      if pl_path.exists(pid_path) then
        kill.kill(pid_path, "-TERM")
      end
    end
  end
}
