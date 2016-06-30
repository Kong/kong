------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016 Mashape Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers

local BIN_PATH = "bin/kong"
local TEST_CONF_PATH = "spec/kong_tests.conf"

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

---------------
-- Conf and DAO
---------------
local conf = assert(conf_loader(TEST_CONF_PATH))
local dao = DAOFactory(conf)
-- make sure migrations are up-to-date
--assert(dao:run_migrations())

-----------------
-- Custom helpers
-----------------
local resty_http_proxy_mt = {}

-- Case insensitive lookup function, returns the value and the original key. Or if not
-- found nil and the search key
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

local function wait_until(f, timeout)
  if type(f) ~= "function" then
    error("arg #1 must be a function", 2)
  end

  timeout = timeout or 2
  local tstart = ngx.time()
  local texp, ok = tstart + timeout

  repeat
    ngx.sleep(0.2)
    ok = f()
  until ok or ngx.time() >= texp

  if not ok then
    error("wait_until() timeout", 2)
  end
end

--- Send a http request. Based on https://github.com/pintsized/lua-resty-http.
-- If `opts.body` is a table and "Content-Type" header contains `application/json`,
-- `www-form-urlencoded`, or `multipart/form-data`, then it will automatically encode the body
-- according to the content type.
-- If `opts.query` is a table, a query string will be constructed from it and appended
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
    -- wrap the read_body() so it caches the result and can be called multiple times
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


--- Creates a http client. Based on https://github.com/pintsized/lua-resty-http.
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
local proxy_client = function()
  return http_client(conf.proxy_ip, conf.proxy_port)
end

--- returns a pre-configured `http_client` for the Kong admin port.
-- @name admin_client
local admin_client = function()
  return http_client(conf.admin_ip, conf.admin_port)
end

local function udp_server(port)
  local threads = require "llthreads2.ex"

  local thread = threads.new({
    function(port)
      local socket = require "socket"
      local server = assert(socket.udp())
      server:settimeout(1)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", port)
      local data = server:receive()
      server:close()
      return data
    end
  }, port or 9999)

  thread:start()

  ngx.sleep(0.1)

  return thread
end

--------------------
-- Custom assertions
--------------------
local say = require "say"
local luassert = require "luassert.assert"

-- wrap assert and create a new kong-assert state table for each call
local old_assert = assert
local kong_state
assert = function(...)
  kong_state = {}
  return old_assert(...)
end
-- tricky part: the assertions below, should not reset the `kong_state` inserted above. Hence
-- we shadow the global assert (patched one) with a local assert (unpatched) to prevent this.
local assert = old_assert

--- Generic modifier "response".
-- Will set a "response" value in the assertion state, so following
-- assertions will operate on the value set.
-- @name response
-- @param response results from `http_client:send` function.
-- @usage
-- local res = assert(client:send { ..your request parameters here ..})
-- local length = assert.response(res).has.header("Content-Length")
local function modifier_response(state, arguments, level)
  assert(arguments.n > 0, "response modifier requires a response object as argument")
  local res = arguments[1]
  assert((type(res) == "table") and (type(res.read_body) == "function"),
    "response modifier requires a response object as argument, got; "..tostring(res))
  kong_state.kong_response = res
  kong_state.kong_request = nil
  return state
end
luassert:register("modifier", "response", modifier_response)

--- Generic modifier "request".
-- Will set a "request" value in the assertion state, so following
-- assertions will operate on the value set.
-- The request must be inside a 'response' from mockbin.org or httpbin.org
-- @name request
-- @param response results from `http_client:send` function. The request will be extracted from the response.
-- @usage
-- local res = assert(client:send { ..your request parameters here ..})
-- local length = assert.request(res).has.header("Content-Length")
local function modifier_request(state, arguments, level)
  local generic = "The assertion 'request' modifier takes a http response object as "..
                  "input to decode the json-body returned by httpbin.org/mockbin.org, "..
                  "to retrieve the proxied request."
  local res = arguments[1]
  assert((type(res) == "table") and (type(res.read_body) == "function"),
    "Expected a http response object, got '"..tostring(res).."'. "..generic)
  local body, err = assert(res:read_body())
  body, err = cjson.decode(body)
  assert(body, "Expected the http response object to have a json encoded body, but decoding gave error '"..tostring(err).."'. "..generic)
  -- check if it is a mockbin request
  if lookup((res.headers or {}),"X-Powered-By") ~= "mockbin" then
    -- not mockbin, so httpbin?
    assert((type(body.url) == "string") and (body.url:find("//httpbin.org", 1, true)),
      "Could not determine the response to be from either mockbin.com or httpbin.org")
  end
  kong_state.kong_request = body
  kong_state.kong_response = nil
  return state
end
luassert:register("modifier", "request", modifier_request)

--- Generic fail assertion. A convenience function for debugging tests, always fails. It will output the
-- values it was called with as a table, with an `n` field to indicate the number of arguments received.
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
-- @param expected The value to search for
-- @param array The array to search for the value
-- @param pattern (optional) If thruthy, then `expected` is matched as a string pattern
-- @returns the index at which the value was found
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
-- @param response (optional) results from `http_client:send` function, alternatively use `response`.
-- @return the response body as a string
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local body = assert.has.status(200, res)             -- or alternativly
-- local body = assert.response(res).has.status(200)    -- does the same
local function res_status(state, args)
  assert(not kong_state.kong_request, "Cannot check statuscode against a request object, only against a response object")
  local expected = args[1]
  local res = args[2] or kong_state.kong_response
  assert(type(expected) == "number", "Expected response code must be a number value. Got; "..tostring(expected))
  assert((type(res) == "table") and (type(res.read_body) == "function"), "Expected a http_client response. Got; "..tostring(res))
  if expected ~= res.status then
    local body, err = res:read_body()
    if not body then body = "Error reading body: "..tostring(err) end
    table.insert(args, 1, body)
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3
    return false
  else
    local body, err = res:read_body()
    local output = body
    if not output then output = "Error reading body: "..tostring(err) end
    output = pl_stringx.strip(output)
    table.insert(args, 1, output)
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3
    return true, {body}
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
]])
say:set("assertion.res_status.positive", [[
Invalid response status code.
Status not expected:
%s
Status received:
%s
Body:
%s
]])
luassert:register("assertion", "status", res_status,
                  "assertion.res_status.negative", "assertion.res_status.positive")
luassert:register("assertion", "res_status", res_status,     -- TODO: remove this, for now will break too many existing tests
                  "assertion.res_status.negative", "assertion.res_status.positive")

--- Checks and returns a json body of an http response/request. Only checks
-- validity of the json, does not check appropriate headers. Setting the target to check 
-- can be done through `request` or `response` (requests are only supported with mockbin.com).
-- @name jsonbody
-- @return the decoded json as a table
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local body = assert.response(res).has.jsonbody()
local function jsonbody(state, args)
  assert((args[1] == nil) and (kong_state.kong_request or kong_state.kong_response), 
    "the `jsonbody` assertion does not take parameters. Use the `response`/`require` modifiers to set the target to operate on")
  if kong_state.kong_response then
    local body = kong_state.kong_response:read_body()
    local json, err = cjson.decode(body)
    if not json then
      table.insert(args, 1, "Error decoding: "..tostring(err).."\nResponse body:"..tostring(body))
      args.n = 1
      return false
    end
    return true, {json}
  else
    assert(kong_state.kong_request.postData, "No post data found in the request. Only mockbin.com is supported!")
    local json, err = cjson.decode(kong_state.kong_request.postData.text)
    if not json then
      table.insert(args, 1, "Error decoding: "..tostring(err).."\nRequest body:"..tostring(kong_state.kong_request.postData.text))
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
-- @param name header name to look for.
-- @see response
-- @see request
-- @return value of the header
local function res_header(state, args)
  local header = args[1]
  local res = args[2] or kong_state.kong_request or kong_state.kong_response
  assert((type(res) == "table") and (type(res.headers) == "table"),
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
-- @return value of the parameter
local function req_query_param(state, args)
  local param = args[1]
  local req = kong_state.kong_request
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
-- @return value of the parameter
local function req_form_param(state, args)
  local param = args[1]
  local req = kong_state.kong_request
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
----------------
local function exec(...)
  local ok, _, stdout, stderr = pl_utils.executeex(...)
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end

local function kong_exec(cmd, env)
  cmd = cmd or ""
  env = env or {}

  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s='%s'", env_vars, k:upper(), v)
  end

  return exec(env_vars.." "..BIN_PATH.." "..cmd)
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
  udp_server = udp_server,
  proxy_client = proxy_client,
  admin_client = admin_client,

  prepare_prefix = function(prefix)
    prefix = prefix or conf.prefix
    return pl_dir.makepath(prefix)
  end,
  clean_prefix = function(prefix)
    prefix = prefix or conf.prefix
    if pl_path.exists(prefix) then
      pl_dir.rmtree(prefix)
    end
  end,
  start_kong = function()
    return kong_exec("start --conf "..TEST_CONF_PATH)
  end,
  stop_kong = function()
    return kong_exec("stop --conf "..TEST_CONF_PATH)
  end,
  kill_all = function()
    dao:truncate_tables() -- truncate nodes table too
    return exec "pkill nginx; pkill serf; pkill dnsmasq"
  end
}