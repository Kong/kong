local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex

local fmt = string.format


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
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable opentelemetry plugin globally pointing to mock server
    bp.plugins:insert({
      name = "opentelemetry",
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

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
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
    assert.matches("00%-" .. trace_id .. "%-%x+-01", json.headers.traceparent)
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
      assert.matches("00%-" .. trace_id .. "%-%x+-01", json.headers.traceparent)
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
      assert.matches("00%-" .. trace_id .. "%-%x+-01", json.headers.traceparent)
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
    assert.matches( ('0'):rep(32-#trace_id) .. trace_id .. ":%x+:" .. span_id .. ":01", json.headers["uber-trace-id"])
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
end)
end
