local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local pretty = require "pl.pretty"
local to_hex = require "resty.string".to_hex

local fmt = string.format

local TCP_PORT = 35001

local function gen_trace_id()
  return to_hex(utils.get_rand_bytes(16))
end


local function gen_span_id()
  return to_hex(utils.get_rand_bytes(8))
end

local function get_span(name, spans)
  for _, span in ipairs(spans) do
    if span.name == name then
      return span
    end
  end
end

local function assert_has_span(name, spans)
  local span = get_span(name, spans)
  assert.is_truthy(span, fmt("\nExpected to find %q span in:\n%s\n",
                             name, pretty.write(spans)))
  return span
end

local function get_span_by_id(spans, id)
  for _, span in ipairs(spans) do
    if span.span_id == id then
      return span
    end
  end
end

local function assert_correct_trace_hierarchy(spans, incoming_span_id)
  for _, span in ipairs(spans) do
    if span.name == "kong" then
      -- if there is an incoming span id, it should be the parent of the root span
      if incoming_span_id then
        assert.equals(incoming_span_id, span.parent_id)
      end

    else
      -- all other spans in this trace should have a local span as parent
      assert.not_equals(incoming_span_id, span.parent_id)
      assert.is_truthy(get_span_by_id(spans, span.parent_id))
    end
  end
end

for _, strategy in helpers.each_strategy() do
for _, instrumentations in ipairs({"all", "off"}) do
for _, sampling_rate in ipairs({1, 0}) do
describe("propagation tests #" .. strategy .. " instrumentations: " .. instrumentations .. " sampling_rate: " .. sampling_rate, function()
  local service
  local proxy_client

  local sampled_flag_w3c
  local sampled_flag_b3
  if instrumentations == "all" and sampling_rate == 1 then
    sampled_flag_w3c = "01"
    sampled_flag_b3 = "1"
  else
    sampled_flag_w3c = "00"
    sampled_flag_b3 = "0"
  end

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" }, { "trace-propagator" })

    service = bp.services:insert()

    local multi_plugin_route = bp.routes:insert({
      hosts = { "multi-plugin" },
      service = service,
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = {id = bp.routes:insert({
        service = service,
        hosts = { "http-route" },
      }).id},
      config = {
        -- fake endpoint, request to backend will sliently fail
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = {id = bp.routes:insert({
        service = service,
        hosts = { "http-route-ignore" },
      }).id},
      config = {
        -- fake endpoint, request to backend will sliently fail
        endpoint = "http://localhost:8080/v1/traces",
        header_type = "ignore",
      }
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = {id = bp.routes:insert({
        service = service,
        hosts = { "http-route-w3c" },
      }).id},
      config = {
        -- fake endpoint, request to backend will sliently fail
        endpoint = "http://localhost:8080/v1/traces",
        header_type = "w3c",
      }
    })

    bp.plugins:insert({
      name = "trace-propagator",
      route = multi_plugin_route,
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = multi_plugin_route,
      config = {
        endpoint = "http://localhost:8080/v1/traces",
        header_type = "ignore",
      }
    })

    helpers.start_kong({
      database = strategy,
      plugins = "bundled, trace-propagator",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      tracing_instrumentations = instrumentations,
      tracing_sampling_rate = sampling_rate,
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("default propagation headers (w3c)", function()
    local r = proxy_client:get("/", {
      headers = {
        host = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.matches("00%-%x+-%x+-" .. sampled_flag_w3c, json.headers.traceparent)
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
      assert.matches(trace_id .. "%-%x+%-" .. sampled_flag_b3 .. "%-%x+", json.headers.b3)
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
      assert.matches(trace_id .. "%-%x+%-" .. sampled_flag_b3, json.headers.b3)
    end)

    it("reflects the disabled sampled flag of the incoming tracing header", function()
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
      -- incoming header has sampled=0: always disabled by
      -- parent-based sampler
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
    assert.matches("00%-" .. trace_id .. "%-%x+-" .. sampled_flag_w3c, json.headers.traceparent)
  end)

  it("defaults to w3c without propagating when header_type set to ignore and w3c headers sent", function()
    local trace_id = gen_trace_id()
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        host = "http-route-ignore"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.is_not_nil(json.headers.traceparent)
    -- incoming trace id is ignored
    assert.not_matches("00%-" .. trace_id .. "%-%x+-" .. sampled_flag_w3c, json.headers.traceparent)
  end)

  it("defaults to w3c without propagating when header_type set to ignore and b3 headers sent", function()
    local trace_id = gen_trace_id()
    local r = proxy_client:get("/", {
      headers = {
        ["x-b3-sampled"] = "1",
        ["x-b3-traceid"] = trace_id,
        host  = "http-route-ignore",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.is_not_nil(json.headers.traceparent)
    -- incoming trace id is ignored
    assert.not_matches("00%-" .. trace_id .. "%-%x+-" .. sampled_flag_w3c, json.headers.traceparent)
  end)

  it("propagates w3c tracing headers when header_type set to w3c", function()
    local trace_id = gen_trace_id()
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        host = "http-route-w3c"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.matches("00%-" .. trace_id .. "%-%x+-" .. sampled_flag_w3c, json.headers.traceparent)
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
    assert.matches( ('0'):rep(32-#trace_id) .. trace_id .. ":%x+:%x+:" .. sampled_flag_w3c, json.headers["uber-trace-id"])
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

  it("propagate spwaned span with ot headers", function()
    local r = proxy_client:get("/", {
      headers = {
        host = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    local traceparent = json.headers["traceparent"]

    local m = assert(ngx.re.match(traceparent, [[00\-([0-9a-f]+)\-([0-9a-f]+)\-([0-9a-f]+)]]))

    assert.same(32, #m[1])
    assert.same(16, #m[2])
    assert.same(sampled_flag_w3c, m[3])
  end)

  it("with multiple plugins, propagates the correct header", function()
    local trace_id = gen_trace_id()

    local r = proxy_client:get("/", {
      headers = {
        ["x-b3-sampled"] = "1",
        ["x-b3-traceid"] = trace_id,
        host = "multi-plugin",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.matches("00%-%x+-" .. json.headers["x-b3-spanid"] .. "%-" .. sampled_flag_w3c, json.headers.traceparent)
  end)
end)
end
end

for _, instrumentation in ipairs({ "request", "request,balancer", "all" }) do
describe("propagation tests with enabled " .. instrumentation .. " instrumentation (issue #11294) #" .. strategy, function()
  local service, route
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" }, { "tcp-trace-exporter" })

    service = bp.services:insert()

    route = bp.routes:insert({
      service = service,
      hosts = { "http-route" },
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = {id = route.id},
      config = {
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    bp.plugins:insert({
      name = "tcp-trace-exporter",
      config = {
        host = "127.0.0.1",
        port = TCP_PORT,
        custom_spans = false,
      }
    })

    helpers.start_kong({
      database = strategy,
      plugins = "bundled, trace-propagator, tcp-trace-exporter",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      tracing_instrumentations = instrumentation,
      tracing_sampling_rate = 1,
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("sets the outgoint parent span's ID correctly", function()
    local trace_id = gen_trace_id()
    local incoming_span_id = gen_span_id()
    local thread = helpers.tcp_server(TCP_PORT)

    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, incoming_span_id),
        host = "http-route"
      },
    })
    local body = assert.response(r).has.status(200)

    local _, res = thread:join()
    assert.is_string(res)
    local spans = cjson.decode(res)

    local parent_span
    if instrumentation == "request" then
      -- balancer instrumentation is not enabled,
      -- the outgoing parent span is the root span
      parent_span = assert_has_span("kong", spans)
    else
      -- balancer instrumentation is enabled,
      -- the outgoing parent span is the balancer span
      parent_span = assert_has_span("kong.balancer", spans)
    end

    local json = cjson.decode(body)
    assert.matches("00%-" .. trace_id .. "%-" .. parent_span.span_id .. "%-01", json.headers.traceparent)

    assert_correct_trace_hierarchy(spans, incoming_span_id)
  end)
end)
end
end
