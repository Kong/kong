------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local cjson = require("cjson.safe")
local say = require("say")
local pl_dir = require("pl.dir")
local pl_file = require("pl.file")
local colors = require("ansicolors")
local luassert = require("luassert.assert")


local conf = require("spec.internal.conf")
local misc = require("spec.internal.misc")


local strip = require("kong.tools.string").strip
local splitlines = require("pl.stringx").splitlines


--------------------
-- Custom assertions
--
-- @section assertions



--- Generic modifier "response".
-- Will set a "response" value in the assertion state, so following
-- assertions will operate on the value set.
-- @function response
-- @param response_obj results from `http_client:send` function (or any of the
-- shortcuts `client:get`, `client:post`, etc).
-- @usage
-- local res = client:get("/request", { .. request options here ..})
-- local response_length = assert.response(res).has.header("Content-Length")
local function modifier_response(state, arguments, level)
  assert(arguments.n > 0,
        "response modifier requires a response object as argument")

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "response modifier requires a response object as argument, got: " .. tostring(res))

  rawset(state, "kong_response", res)
  rawset(state, "kong_request", nil)

  return state
end
luassert:register("modifier", "response", modifier_response)


--- Generic modifier "request".
-- Will set a "request" value in the assertion state, so following
-- assertions will operate on the value set.
--
-- The request must be inside a 'response' from the `mock_upstream`. If a request
-- is send to the `mock_upstream` endpoint `"/request"`, it will echo the request
-- received in the body of the response.
-- @function request
-- @param response_obj results from `http_client:send` function (or any of the
-- shortcuts `client:get`, `client:post`, etc).
-- @usage
-- local res = client:post("/request", {
--               headers = { ["Content-Type"] = "application/json" },
--               body = { hello = "world" },
--             })
-- local request_length = assert.request(res).has.header("Content-Length")
local function modifier_request(state, arguments, level)
  local generic = "The assertion 'request' modifier takes a http response"
                .. " object as input to decode the json-body returned by"
                .. " mock_upstream, to retrieve the proxied request."

  local res = arguments[1]

  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http response object, got '" .. tostring(res) .. "'. " .. generic)

  local body, request, err
  body = assert(res:read_body())
  request, err = cjson.decode(body)

  assert(request, "Expected the http response object to have a json encoded body,"
                  .. " but decoding gave error '" .. tostring(err) .. "'. Obtained body: "
                  .. body .. "\n." .. generic)


  if misc.lookup((res.headers or {}),"X-Powered-By") ~= "mock_upstream" then
    error("Could not determine the response to be from mock_upstream")
  end

  rawset(state, "kong_request", request)
  rawset(state, "kong_response", nil)

  return state
end
luassert:register("modifier", "request", modifier_request)


--- Generic fail assertion. A convenience function for debugging tests, always
-- fails. It will output the values it was called with as a table, with an `n`
-- field to indicate the number of arguments received. See also `intercept`.
-- @function fail
-- @param ... any set of parameters to be displayed with the failure
-- @see intercept
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
-- @function contains
-- @param expected The value to search for
-- @param array The array to search for the value
-- @param pattern (optional) If truthy, then `expected` is matched as a Lua string
-- pattern
-- @return the array index at which the value was found
-- @usage
-- local arr = { "one", "three" }
-- local i = assert.contains("one", arr)        --> passes; i == 1
-- local i = assert.contains("two", arr)        --> fails
-- local i = assert.contains("ee$", arr, true)  --> passes; i == 2
local function contains(state, args)
  local expected, arr, pattern = misc.unpack(args)
  local found
  for i = 1, #arr do
    if (pattern and string.match(arr[i], expected)) or arr[i] == expected then
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


local function copy_errlog(errlog_path)
  local file_path = "Unknown path"
  local line_number = "Unknown line"
  local errlog_cache_dir = os.getenv("SPEC_ERRLOG_CACHE_DIR") or "/tmp/kong_errlog_cache"

  local ok, err = pl_dir.makepath(errlog_cache_dir)
  assert(ok, "makepath failed: " .. tostring(err))

  local info = debug.getinfo(4, "Sl")
  if info then
    file_path = info.source:gsub("^@", "")
    line_number = info.currentline
  end

  if string.find(file_path, '/', nil, true) then
    file_path = string.gsub(file_path, '/', '_')
  end
  file_path = errlog_cache_dir .. "/" .. file_path:gsub("%.lua$", "_") .. "line_" .. line_number .. '.log'

  ok, err = pl_file.copy(errlog_path, file_path)
  if ok then
    print(colors("%{yellow}Log saved as: " .. file_path .. "%{reset}"))
  else
    print(colors("%{red}Failed to save error log for test " .. file_path .. ": " .. err))
  end
end


--- Assertion to check the status-code of a http response.
-- @function status
-- @param expected the expected status code
-- @param response (optional) results from `http_client:send` function,
-- alternatively use `response`.
-- @return the response body as a string, for a json body see `jsonbody`.
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local body = assert.has.status(200, res)             -- or alternativly
-- local body = assert.response(res).has.status(200)    -- does the same
local function res_status(state, args)
  assert(not rawget(state, "kong_request"),
         "Cannot check statuscode against a request object,"
       .. " only against a response object")

  local expected = args[1]
  local res = args[2] or rawget(state, "kong_response")

  assert(type(expected) == "number",
         "Expected response code must be a number value. Got: " .. tostring(expected))
  assert(type(res) == "table" and type(res.read_body) == "function",
         "Expected a http_client response. Got: " .. tostring(res))

  if expected ~= res.status then
    local body, err = res:read_body()
    if not body then body = "Error reading body: " .. err end
    table.insert(args, 1, strip(body))
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3

    if res.status == 500 then
      copy_errlog(conf.nginx_err_logs)

      -- on HTTP 500, we can try to read the server's error logs
      -- for debugging purposes (very useful for travis)
      local str = pl_file.read(conf.nginx_err_logs)
      if not str then
        return false -- no err logs to read in this prefix
      end

      local lines_t = splitlines(str)
      local str_t = {}
      -- filter out debugs as they are not usually useful in this context
      for i = 1, #lines_t do
        if not lines_t[i]:match(" %[debug%] ") then
          table.insert(str_t, lines_t[i])
        end
      end

      local first_line = #str_t - math.min(60, #str_t) + 1
      local msg_t = {"\nError logs (" .. conf.nginx_err_logs .. "), only last 60 non-debug logs are displayed:"}
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
    if not output then output = "Error reading body: " .. err end
    output = strip(output)
    table.insert(args, 1, output)
    table.insert(args, 1, res.status)
    table.insert(args, 1, expected)
    args.n = 3
    return true, { strip(body) }
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
-- to check can be done through the `request` and `response` modifiers.
--
-- For a non-json body, see the `status` assertion.
-- @function jsonbody
-- @return the decoded json as a table
-- @usage
-- local res = assert(client:send { .. your request params here .. })
-- local json_table = assert.response(res).has.jsonbody()
local function jsonbody(state, args)
  assert(args[1] == nil and rawget(state, "kong_request") or rawget(state, "kong_response"),
         "the `jsonbody` assertion does not take parameters. " ..
         "Use the `response`/`require` modifiers to set the target to operate on")

  if rawget(state, "kong_response") then
    local body = rawget(state, "kong_response"):read_body()
    local json, err = cjson.decode(body)
    if not json then
      table.insert(args, 1, "Error decoding: " .. tostring(err) .. "\nResponse body:" .. body)
      args.n = 1
      return false
    end
    return true, {json}

  else
    local r = rawget(state, "kong_request")
    if r.post_data
    and (r.post_data.kind == "json" or r.post_data.kind == "json (error)")
    and r.post_data.params
    then
      local pd = r.post_data
      return true, { { params = pd.params, data = pd.text, error = pd.error, kind = pd.kind } }

    else
      error("No json data found in the request")
    end
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


--- Asserts that a named header in a `headers` subtable exists.
-- Header name comparison is done case-insensitive.
-- @function header
-- @param name header name to look for (case insensitive).
-- @see response
-- @see request
-- @return value of the header
-- @usage
-- local res = client:get("/request", { .. request options here ..})
-- local resp_header_value = assert.response(res).has.header("Content-Length")
-- local req_header_value = assert.request(res).has.header("Content-Length")
local function res_header(state, args)
  local header = args[1]
  local res = args[2] or rawget(state, "kong_request") or rawget(state, "kong_response")
  assert(type(res) == "table" and type(res.headers) == "table",
         "'header' assertion input does not contain a 'headers' subtable")
  local value = misc.lookup(res.headers, header)
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
-- An assertion to look for a query parameter in a query string.
-- Parameter name comparison is done case-insensitive.
-- @function queryparam
-- @param name name of the query parameter to look up (case insensitive)
-- @return value of the parameter
-- @usage
-- local res = client:get("/request", {
--               query = { hello = "world" },
--             })
-- local param_value = assert.request(res).has.queryparam("hello")
local function req_query_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'queryparam' assertion only works with a request object")
  local params
  if type(req.uri_args) == "table" then
    params = req.uri_args

  else
    error("No query parameters found in request object")
  end
  local value = misc.lookup(params, param)
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
-- Adds an assertion to look for a urlencoded form parameter in a request.
-- Parameter name comparison is done case-insensitive. Use the `request` modifier to set
-- the request to operate on.
-- @function formparam
-- @param name name of the form parameter to look up (case insensitive)
-- @return value of the parameter
-- @usage
-- local r = assert(proxy_client:post("/request", {
--   body    = {
--     hello = "world",
--   },
--   headers = {
--     host             = "mock_upstream",
--     ["Content-Type"] = "application/x-www-form-urlencoded",
--   },
-- })
-- local value = assert.request(r).has.formparam("hello")
-- assert.are.equal("world", value)
local function req_form_param(state, args)
  local param = args[1]
  local req = rawget(state, "kong_request")
  assert(req, "'formparam' assertion can only be used with a mock_upstream request object")

  local value
  if req.post_data
  and (req.post_data.kind == "form" or req.post_data.kind == "multipart-form")
  then
    value = misc.lookup(req.post_data.params or {}, param)
  else
    error("Could not determine the request to be from either mock_upstream")
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


---
-- Assertion to ensure a value is greater than a base value.
-- @function is_gt
-- @param base the base value to compare against
-- @param value the value that must be greater than the base value
local function is_gt(state, arguments)
  local expected = arguments[1]
  local value = arguments[2]

  arguments[1] = value
  arguments[2] = expected

  return value > expected
end
say:set("assertion.gt.negative", [[
Given value (%s) should be greater than expected value (%s)
]])
say:set("assertion.gt.positive", [[
Given value (%s) should not be greater than expected value (%s)
]])
luassert:register("assertion", "gt", is_gt,
                  "assertion.gt.negative",
                  "assertion.gt.positive")


---
-- Matcher to ensure a value is greater than a base value.
-- @function is_gt_matcher
-- @param base the base value to compare against
-- @param value the value that must be greater than the base value
local function is_gt_matcher(state, arguments)
  local expected = arguments[1]
  return function(value)
    return value > expected
  end
end
luassert:register("matcher", "gt", is_gt_matcher)


--- Generic modifier "certificate".
-- Will set a "certificate" value in the assertion state, so following
-- assertions will operate on the value set.
-- @function certificate
-- @param cert The cert text
-- @see cn
-- @usage
-- assert.certificate(cert).has.cn("ssl-example.com")
local function modifier_certificate(state, arguments, level)
  local generic = "The assertion 'certficate' modifier takes a cert text"
                .. " as input to validate certificate parameters"
                .. " against."
  local cert = arguments[1]
  assert(type(cert) == "string",
         "Expected a certificate text, got '" .. tostring(cert) .. "'. " .. generic)
  rawset(state, "kong_certificate", cert)
  return state
end
luassert:register("modifier", "certificate", modifier_certificate)


--- Assertion to check whether a CN is matched in an SSL cert.
-- @function cn
-- @param expected The CN value
-- @param cert The cert text
-- @return the CN found in the cert
-- @see certificate
-- @usage
-- assert.cn("ssl-example.com", cert)
--
-- -- alternative:
-- assert.certificate(cert).has.cn("ssl-example.com")
local function assert_cn(state, args)
  local expected = args[1]
  if args[2] and rawget(state, "kong_certificate") then
    error("assertion 'cn' takes either a 'certificate' modifier, or 2 parameters, not both")
  end
  local cert = args[2] or rawget(state, "kong_certificate")
  local cn = string.match(cert, "CN%s*=%s*([^%s,]+)")
  args[2] = cn or "(CN not found in certificate)"
  args.n = 2
  return cn == expected
end
say:set("assertion.cn.negative", [[
Expected certificate to have the given CN value.
Expected CN:
%s
Got instead:
%s
]])
say:set("assertion.cn.positive", [[
Expected certificate to not have the given CN value.
Expected CN to not be:
%s
Got instead:
%s
]])
luassert:register("assertion", "cn", assert_cn,
                  "assertion.cn.negative",
                  "assertion.cn.positive")


do
  --- Generic modifier "logfile"
  -- Will set an "errlog_path" value in the assertion state.
  -- @function logfile
  -- @param path A path to the log file (defaults to the test prefix's
  -- errlog).
  -- @see line
  -- @see clean_logfile
  -- @usage
  -- assert.logfile("./my/logfile.log").has.no.line("[error]", true)
  local function modifier_errlog(state, args)
    local errlog_path = args[1] or conf.nginx_err_logs

    assert(type(errlog_path) == "string", "logfile modifier expects nil, or " ..
                                          "a string as argument, got: "      ..
                                          type(errlog_path))

    rawset(state, "errlog_path", errlog_path)

    return state
  end

  luassert:register("modifier", "errlog", modifier_errlog) -- backward compat
  luassert:register("modifier", "logfile", modifier_errlog)

  local function substr(subject, pattern)
    if subject:find(pattern, nil, true) ~= nil then
      return subject
    end
  end

  local function re_match(subject, pattern)
    local pos, _, err = ngx.re.find(subject, pattern, "oj")
    if err then
      error(("invalid regex provided to logfile assertion %q: %s")
            :format(pattern, err), 5)
    end

    if pos then
      return subject
    end
  end

  local function find_in_file(fpath, pattern, matcher)
    local fh = assert(io.open(fpath, "r"))
    local found

    for line in fh:lines() do
      if matcher(line, pattern) then
        found = line
        break
      end
    end

    fh:close()

    return found
  end


  --- Assertion checking if any line from a file matches the given regex or
  -- substring.
  -- @function line
  -- @param regex The regex to evaluate against each line.
  -- @param plain If true, the regex argument will be considered as a plain
  -- string.
  -- @param timeout An optional timeout after which the assertion will fail if
  -- reached.
  -- @param fpath An optional path to the file (defaults to the filelog
  -- modifier)
  -- @see logfile
  -- @see clean_logfile
  -- @usage
  -- helpers.clean_logfile()
  --
  -- -- run some tests here
  --
  -- assert.logfile().has.no.line("[error]", true)
  local function match_line(state, args)
    local regex = args[1]
    local plain = args[2]
    local timeout = args[3] or 2
    local fpath = args[4] or rawget(state, "errlog_path")

    assert(type(regex) == "string",
           "Expected the regex argument to be a string")
    assert(type(fpath) == "string",
           "Expected the file path argument to be a string")
    assert(type(timeout) == "number" and timeout >= 0,
           "Expected the timeout argument to be a number >= 0")


    local matcher = plain and substr or re_match

    local found = find_in_file(fpath, regex, matcher)
    local deadline = ngx.now() + timeout

    while not found and ngx.now() <= deadline do
      ngx.sleep(0.05)
      found = find_in_file(fpath, regex, matcher)
    end

    args[1] = fpath
    args[2] = regex
    args.n = 2

    if found then
      args[3] = found
      args.n = 3
    end

    return found
  end

  say:set("assertion.match_line.negative", misc.unindent [[
    Expected file at:
    %s
    To match:
    %s
  ]])
  say:set("assertion.match_line.positive", misc.unindent [[
    Expected file at:
    %s
    To not match:
    %s
    But matched line:
    %s
  ]])
  luassert:register("assertion", "line", match_line,
                    "assertion.match_line.negative",
                    "assertion.match_line.positive")
end


--- Assertion to check whether a string matches a regular expression
-- @function match_re
-- @param string the string
-- @param regex the regular expression
-- @return true or false
-- @usage
-- assert.match_re("foobar", [[bar$]])
--

local function match_re(_, args)
  local string = args[1]
  local regex = args[2]
  assert(type(string) == "string",
    "Expected the string argument to be a string")
  assert(type(regex) == "string",
    "Expected the regex argument to be a string")
  local from, _, err = ngx.re.find(string, regex)
  if err then
    error(err)
  end
  if from then
    table.insert(args, 1, string)
    table.insert(args, 1, regex)
    args.n = 2
    return true
  else
    return false
  end
end

say:set("assertion.match_re.negative", misc.unindent [[
    Expected log:
    %s
    To match:
    %s
  ]])
say:set("assertion.match_re.positive", misc.unindent [[
    Expected log:
    %s
    To not match:
    %s
    But matched line:
    %s
  ]])
luassert:register("assertion", "match_re", match_re,
  "assertion.match_re.negative",
  "assertion.match_re.positive")


---
-- Assertion to partially compare two lua tables.
-- @function partial_match
-- @param partial_table the table with subset of fields expect to match
-- @param full_table the full table that should contain partial_table and potentially other fields
local function partial_match(state, arguments)

  local function deep_matches(t1, t2, parent_keys)
    for key, v in pairs(t1) do
        local compound_key = (parent_keys and parent_keys .. "." .. key) or key
        if type(v) == "table" then
          local ok, compound_key, v1, v2 = deep_matches(t1[key], t2[key], compound_key)
            if not ok then
              return ok, compound_key, v1, v2
            end
        else
          if (state.mod == true and t1[key] ~= t2[key]) or (state.mod == false and t1[key] == t2[key]) then
            return false, compound_key, t1[key], t2[key]
          end
        end
    end

    return true
  end

  local partial_table = arguments[1]
  local full_table = arguments[2]

  local ok, compound_key, v1, v2 = deep_matches(partial_table, full_table)

  if not ok then
    arguments[1] = compound_key
    arguments[2] = v1
    arguments[3] = v2
    arguments.n = 3

    return not state.mod
  end

  return state.mod
end

say:set("assertion.partial_match.negative", [[
Values at key %s should not be equal
]])
say:set("assertion.partial_match.positive", [[
Values at key %s should be equal but are not.
Expected: %s, given: %s
]])
luassert:register("assertion", "partial_match", partial_match,
                  "assertion.partial_match.positive",
                  "assertion.partial_match.negative")


-- the same behivor with other modules
return true
