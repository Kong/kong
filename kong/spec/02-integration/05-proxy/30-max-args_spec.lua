local helpers = require "spec.helpers"
local clone = require "table.clone"


local encode_args = ngx.encode_args
local tostring = tostring
local assert = assert
local ipairs = ipairs


local lazy_teardown = lazy_teardown
local before_each = before_each
local after_each = after_each
local lazy_setup = lazy_setup
local describe = describe
local it = it


local HOST = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port


local function get_parameters(n)
  local query = {}

  for i = 1, n do
    query["a" .. i] = "v" .. i
  end

  local body = encode_args(query)
  local headers = clone(query)
  headers["a1"] = nil
  headers["a2"] = nil
  headers["a3"] = nil
  headers["a4"] = nil

  headers["content-length"] = tostring(#body)
  headers["content-type"] = "application/x-www-form-urlencoded"
  headers["user-agent"] = "kong"
  headers["host"] = HOST

  return {
    query = query,
    headers = headers,
    body = body,
  }
end


local function get_response_headers(n)
  local headers = {}

  for i = 1, n - 2 do
    headers["a" .. i] = "v" .. i
  end

  headers["content-length"] = "0"
  headers["connection"] = "keep-alive"

  return headers
end


local function validate(client_args_count, params, body, headers)
  assert.is.equal(client_args_count, body.client_args_count)

  assert.same(params.query, body.kong.uri_args)
  assert.same(params.query, body.ngx.uri_args)

  assert.same(params.headers, body.kong.request_headers)
  assert.same(params.headers, body.ngx.request_headers)

  local response_headers = get_response_headers(client_args_count)

  assert.same(response_headers, body.kong.response_headers)
  assert.same(response_headers, body.ngx.response_headers)

  headers["Content-Length"] = nil
  headers["Connection"] = nil
  headers["Content-Type"] = nil
  headers["Date"] = nil
  headers["Server"] = nil
  headers["X-Kong-Response-Latency"] = nil

  response_headers["content-length"] = nil
  response_headers["connection"] = nil

  assert.same(response_headers, headers)

  assert.same(params.query, body.kong.post_args)
  assert.same(params.query, body.ngx.post_args)

  assert.logfile().has.no.line("request headers truncated", true, 0.5)
  assert.logfile().has.no.line("uri args truncated", true, 0.1)
  assert.logfile().has.no.line("post args truncated", true, 0.1)
  assert.logfile().has.no.line("response headers truncated", true, 0.1)
end


local function validate_truncated(client_args_count, params, body, headers)
  assert.is.equal(client_args_count, body.client_args_count)

  assert.is_not.same(params.query, body.kong.uri_args)
  assert.is_not.same(params.query, body.ngx.uri_args)

  assert.is_not.same(params.headers, body.kong.request_headers)
  assert.is_not.same(params.headers, body.ngx.request_headers)

  assert.is_not.same(get_response_headers(client_args_count), body.kong.response_headers)
  assert.is_not.same(get_response_headers(client_args_count), body.ngx.response_headers)

  local response_headers = get_response_headers(client_args_count)

  headers["Content-Length"] = nil
  headers["Connection"] = nil
  headers["Content-Type"] = nil
  headers["Date"] = nil
  headers["Server"] = nil
  headers["X-Kong-Response-Latency"] = nil

  response_headers["content-length"] = nil
  response_headers["connection"] = nil

  assert.same(response_headers, headers)

  assert.is_not.same(params.query, body.kong.post_args)
  assert.is_not.same(params.query, body.ngx.post_args)

  assert.logfile().has.line("request headers truncated", true, 0.5)
  assert.logfile().has.line("uri args truncated", true, 0.1)
  assert.logfile().has.line("post args truncated", true, 0.1)
  assert.logfile().has.line("response headers truncated", true, 0.1)
end


local function validate_proxy(params, body, truncated)
  assert.same(params.query, body.uri_args)

  local request_headers = body.headers

  request_headers["connection"] = nil
  request_headers["x-forwarded-for"] = nil
  request_headers["x-forwarded-host"] = nil
  request_headers["x-forwarded-path"] = nil
  request_headers["x-forwarded-port"] = nil
  request_headers["x-forwarded-prefix"] = nil
  request_headers["x-forwarded-proto"] = nil
  request_headers["x-real-ip"] = nil
  request_headers["via"] = nil

  assert.same(params.headers, request_headers)
  assert.same(params.query, body.uri_args)
  assert.same(params.query, body.post_data.params)

  if truncated then
    assert.logfile().has.line("truncated", true, 0.5)
  else
    assert.logfile().has.no.line("truncated", true, 0.5)
  end
end


for _, strategy in helpers.each_strategy() do
  for _, n in ipairs({ 50, 100, 200 }) do
    describe("max args [#" .. strategy .. "] (" .. n .. " parameters)", function()
      local client
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "plugins",
          "routes",
          "services",
        }, {
          "max-args"
        })

        local service = assert(bp.services:insert({
          url = helpers.mock_upstream_url
        }))

        bp.routes:insert({
          service = service,
          paths = { "/proxy" }
        })

        local route = bp.routes:insert({
          paths = { "/max-args" }
        })

        assert(bp.plugins:insert({
          name = "max-args",
          route = { id = route.id },
        }))

        helpers.start_kong({
          database = strategy,
          plugins = "bundled, max-args",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          lua_max_resp_headers = n ~= 100 and n or nil,
          lua_max_req_headers = n ~= 100 and n or nil,
          lua_max_uri_args = n ~= 100 and n or nil,
          lua_max_post_args = n ~= 100 and n or nil,
          log_level = "debug",
          headers_upstream = "off",
          headers = "off"
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        helpers.clean_logfile()
        client = helpers.proxy_client()
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      it("no truncation when using " .. n .. " parameters", function()
        local params = get_parameters(n)
        local res = client:post("/max-args", params)
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        validate(n, params, body, res.headers)
      end)

      it("truncation when using " .. n + 1 .. " parameters", function()
        local params = get_parameters(n + 1)
        local res = client:post("/max-args", params)
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        validate_truncated(n + 1, params, body, res.headers)
      end)

      it("no truncation when using " .. n .. " parameters when proxying", function()
        local params = get_parameters(n)
        local res = client:post("/proxy", params)
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        validate_proxy(params, body, false)
      end)

      it("no truncation when using " .. n + 1 .. " parameters when proxying", function()
        local params = get_parameters(n + 1)
        local res = client:post("/proxy", params)
        assert.response(res).has.status(200)
        local body = assert.response(res).has.jsonbody()
        validate_proxy(params, body, true)
      end)
    end)
  end
end
