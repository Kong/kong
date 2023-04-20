-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex

local fmt = string.format

local TCP_PORT = 35001


local function gen_trace_id()
  return to_hex(utils.get_rand_bytes(16))
end


local function gen_span_id()
  return to_hex(utils.get_rand_bytes(8))
end


for _, strategy in helpers.each_strategy() do
describe("propagation tests #" .. strategy, function()
  local service
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" }, { "datadog-tracing",  "tcp-trace-exporter"})

    -- enable datadog-tracing plugin globally pointing to mock server
    bp.plugins:insert({
      name = "datadog-tracing",
      config = {
        -- fake endpoint, request to backend will sliently fail
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    service = bp.services:insert()

    -- kong (http) mock upstream
    bp.routes:insert({
      service = service,
      hosts = { "http-route" },
    })

    local trace_exp_route = bp.routes:insert({
      service = service,
      hosts = { "trace-exporter" },
    })

    bp.plugins:insert({
      name = "tcp-trace-exporter",
      route = trace_exp_route,
      config = {
        host = "127.0.0.1",
        port = TCP_PORT,
        custom_spans = false,
      }
    })

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled,datadog-tracing,tcp-trace-exporter",
      tracing_instrumentations = "all",
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("default propagation headers (datadog)", function()
    local r = proxy_client:get("/", {
      headers = {
        host = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    assert.matches("%x+", json.headers["x-datadog-trace-id"])
  end)

  it("propagates tracing headers (b3 request)", function()
    local trace_id = gen_trace_id()
    local r = proxy_client:get("/", {
      headers = {
        ["x-b3-sampled"] = "1",
        ["x-b3-traceid"] = trace_id,
        host  = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.equals(trace_id, json.headers["x-b3-traceid"])
  end)

  describe("propagates tracing headers (b3-single request)", function()
    it("with parent_id", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()
      local parent_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1%-%x+", json.headers.b3)
    end)

    it("without parent_id", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1", json.headers.b3)
    end)

    it("with disabled sampling", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-0", trace_id, span_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-0", json.headers.b3)
    end)
  end)

  it("propagates w3c tracing headers", function()
    local trace_id = gen_trace_id() -- w3c only admits 16-byte trace_ids
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        host = "http-route"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.matches("00%-" .. trace_id .. "%-%x+-01", json.headers.traceparent)
  end)

  it("propagates jaeger tracing headers", function()
    local trace_id = gen_trace_id()
    local span_id = gen_span_id()
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        ["uber-trace-id"] = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "1"),
        host = "http-route"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    -- Trace ID is left padded with 0 for assert
    assert.matches( ('0'):rep(32-#trace_id) .. trace_id .. ":%x+:%x+:01", json.headers["uber-trace-id"])
  end)

  it("propagates ot headers", function()
    local trace_id = gen_trace_id()
    local span_id = gen_span_id()
    local r = proxy_client:get("/", {
      headers = {
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
        host = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    assert.equals(trace_id, json.headers["ot-tracer-traceid"])
  end)

  it("propagates balancer span", function()
    local thread = helpers.tcp_server(TCP_PORT)
    local trace_id = gen_trace_id()
    local parent_id = gen_span_id()
    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        host = "trace-exporter"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    local ok, res = thread:join()
    assert.True(ok)
    assert.is_string(res)

    local spans = cjson.decode(res)
    local balancer_span

    for _, s in ipairs(spans) do
      if s.name == "kong.balancer" then
        balancer_span = s
      end
    end
    assert.is_not_nil(balancer_span)
    local expected_traceparent = "00-" .. trace_id .. "-" .. balancer_span.span_id .. "-01"
    assert.equals(expected_traceparent, json.headers.traceparent)
  end)
end)
end
