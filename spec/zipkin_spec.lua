local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex


-- Transform zipkin annotations into a hash of timestamps. It assumes no repeated values
-- input: { { value = x, timestamp = y }, { value = x2, timestamp = y2 } }
-- output: { x = y, x2 = y2 }
local function annotations_to_hash(annotations)
  local hash = {}
  for _, a in ipairs(annotations) do
    assert(not hash[a.value], "duplicated annotation: " .. a.value)
    hash[a.value] = a.timestamp
  end
  return hash
end


local function assert_is_integer(number)
  assert.equals("number", type(number))
  assert.equals(number, math.floor(number))
end


local function gen_trace_id()
  return to_hex(utils.get_rand_bytes(8, true))
end


for _, strategy in helpers.each_strategy() do
describe("integration tests with zipkin server [#" .. strategy .. "]", function()
  local proxy_client_grpc
  local route, grpc_route
  local zipkin_client
  local proxy_client

  -- the following assertions should be true on any span list, even in error mode
  local function assert_span_invariants(request_span, proxy_span, expected_name)
    -- request_span
    assert.same("table", type(request_span))
    assert.same("string", type(request_span.id))
    assert.same(expected_name, request_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("SERVER", request_span.kind)

    assert.same("string", type(request_span.traceId))
    assert.truthy(request_span.traceId:match("^%x+$"))
    assert_is_integer(request_span.timestamp)

    if request_span.duration and proxy_span.duration then
      assert.truthy(request_span.duration >= proxy_span.duration)
    end

    assert.equals(2, #request_span.annotations)
    local rann = annotations_to_hash(request_span.annotations)
    assert_is_integer(rann["krs"])
    assert_is_integer(rann["krf"])
    assert.truthy(rann["krs"] <= rann["krf"])

    assert.same({ serviceName = "kong" }, request_span.localEndpoint)

    -- proxy_span
    assert.same("table", type(proxy_span))
    assert.same("string", type(proxy_span.id))
    assert.same(request_span.name .. " (proxy)", proxy_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("CLIENT", proxy_span.kind)

    assert.same("string", type(proxy_span.traceId))
    assert.truthy(proxy_span.traceId:match("^%x+$"))
    assert_is_integer(proxy_span.timestamp)

    if request_span.duration and proxy_span.duration then
      assert.truthy(proxy_span.duration >= 0)
    end

    assert.equals(6, #proxy_span.annotations)
    local pann = annotations_to_hash(proxy_span.annotations)

    assert_is_integer(pann["kas"])
    assert_is_integer(pann["kaf"])
    assert_is_integer(pann["khs"])
    assert_is_integer(pann["khf"])
    assert_is_integer(pann["kbs"])
    assert_is_integer(pann["kbf"])

    assert.truthy(pann["kas"] <= pann["kaf"])
    assert.truthy(pann["khs"] <= pann["khf"])
    assert.truthy(pann["kbs"] <= pann["kbf"])

    assert.truthy(pann["khs"] <= pann["kbs"])
  end


  setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      config = {
        sample_ratio = 1,
        http_endpoint = "http://127.0.0.1:9411/api/v2/spans",
      }
    })

    local service = bp.services:insert {
      name = "mock-http-service",
    }

    -- kong (http) mock upstream
    route = bp.routes:insert({
      service = service,
      hosts = { "mock-http-route" },
      preserve_host = true,
    })

    -- grpc upstream
    local grpc_service = bp.services:insert {
      name = "grpc-service",
      url = "grpc://localhost:15002",
    }

    grpc_route = bp.routes:insert {
      service = grpc_service,
      protocols = { "grpc" },
      hosts = { "mock-grpc-route" },
    }

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    proxy_client = helpers.proxy_client()
    proxy_client_grpc = helpers.proxy_client_grpc()
    zipkin_client = helpers.http_client("127.0.0.1", 9411)
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("generates spans, tags and annotations for regular requests", function()
    local trace_id = gen_trace_id()

    local r = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["x-b3-traceid"] = trace_id,
        ["x-b3-sampled"] = "1",
        host  = "mock-http-route",
      },
    })
    assert.response(r).has.status(200)

    local spans
    helpers.wait_until(function()
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == 3
    end)

    local balancer_span, proxy_span, request_span = spans[1], spans[2], spans[3]
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get")

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({
      ["http.method"] = "GET",
      ["http.path"] = "/",
      ["http.status_code"] = "200", -- found (matches server status)
      lc = "kong"
    }, request_tags)
    local consumer_port = request_span.remoteEndpoint.port
    assert_is_integer(consumer_port)
    assert.same({
      ipv4 = "127.0.0.1",
      port = consumer_port,
    }, request_span.remoteEndpoint)

    -- specific assertions for proxy_span
    assert.same(proxy_span.tags["kong.route"], route.id)
    assert.same(proxy_span.tags["peer.hostname"], "127.0.0.1")

    assert.same({
      ipv4 = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
      serviceName = "mock-http-service",
    },
    proxy_span.remoteEndpoint)

    -- specific assertions for balancer_span
    assert.equals(balancer_span.parentId, request_span.id)
    assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
    assert.equals("number", type(balancer_span.timestamp))

    if balancer_span.duration then
      assert.equals("number", type(balancer_span.duration))
    end

    assert.same({
      ipv4 = helpers.mock_upstream_host,
      port = helpers.mock_upstream_port,
      serviceName = "mock-http-service",
    },
    balancer_span.remoteEndpoint)
    assert.same({ serviceName = "kong" }, balancer_span.localEndpoint)
    assert.same({
      ["kong.balancer.try"] = "1",
      ["kong.route"] = route.id,
      ["kong.service"] = route.service.id,
    }, balancer_span.tags)
  end)

  it("generates spans, tags and annotations for regular requests (#grpc)", function()
    local trace_id = gen_trace_id()

    local ok, resp = proxy_client_grpc({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-H"] = "'x-b3-traceid: " .. trace_id .. "' -H 'x-b3-sampled: 1'",
        ["-authority"] = "mock-grpc-route",
      }
    })
    assert.truthy(ok)
    assert.truthy(resp)

    local spans
    helpers.wait_until(function()
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == 3
    end)

    local balancer_span, proxy_span, request_span = spans[1], spans[2], spans[3]
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "post")

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil

    assert.same({
      ["http.method"] = "POST",
      ["http.path"] = "/hello.HelloService/SayHello",
      ["http.status_code"] = "200", -- found (matches server status)
      lc = "kong"
    }, request_tags)
    local consumer_port = request_span.remoteEndpoint.port
    assert_is_integer(consumer_port)
    assert.same({
      ipv4 = "127.0.0.1",
      port = consumer_port,
    }, request_span.remoteEndpoint)

    -- specific assertions for proxy_span
    assert.same(proxy_span.tags["kong.route"], grpc_route.id)
    assert.same(proxy_span.tags["peer.hostname"], "localhost")

    assert.same({
      ipv4 = "127.0.0.1",
      port = 15002,
      serviceName = "grpc-service",
    },
    proxy_span.remoteEndpoint)

    -- specific assertions for balancer_span
    assert.equals(balancer_span.parentId, request_span.id)
    assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
    assert_is_integer(balancer_span.timestamp)

    if balancer_span.duration then
      assert_is_integer(balancer_span.duration)
    end

    assert.same({
      ipv4 = "127.0.0.1",
      port = 15002,
      serviceName = "grpc-service",
    },
    balancer_span.remoteEndpoint)
    assert.same({ serviceName = "kong" }, balancer_span.localEndpoint)
    assert.same({
      ["kong.balancer.try"] = "1",
      ["kong.service"] = grpc_route.service.id,
      ["kong.route"] = grpc_route.id,
    }, balancer_span.tags)
  end)

  it("generates spans, tags and annotations for non-matched requests", function()
    local trace_id = gen_trace_id()

    local r = assert(proxy_client:send {
      method  = "GET",
      path    = "/foobar",
      headers = {
        ["x-b3-traceid"] = trace_id,
        ["x-b3-sampled"] = "1",
      },
    })
    assert.response(r).has.status(404)

    local spans
    helpers.wait_until(function()
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == 2
    end)

    local proxy_span, request_span = spans[1], spans[2]

    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get")

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({
      ["http.method"] = "GET",
      ["http.path"] = "/foobar",
      ["http.status_code"] = "404", -- note that this was "not found"
      lc = "kong"
    }, request_tags)
    local consumer_port = request_span.remoteEndpoint.port
    assert_is_integer(consumer_port)
    assert.same({ ipv4 = "127.0.0.1", port = consumer_port }, request_span.remoteEndpoint)

    -- specific assertions for proxy_span
    assert.is_nil(proxy_span.tags)
    assert.is_nil(proxy_span.remoteEndpoint)
    assert.same({ serviceName = "kong" }, proxy_span.localEndpoint)
  end)

  it("propagates b3 headers for non-matched requests", function()
    local trace_id = gen_trace_id()

    local r = assert(proxy_client:send {
      method  = "GET",
      path    = "/foobar",
      headers = {
        ["x-b3-traceid"] = trace_id,
        ["x-b3-sampled"] = "1",
      },
    })
    assert.response(r).has.status(404)

    local spans
    helpers.wait_until(function()
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == 2
    end)

    for _, v in ipairs(spans) do
      assert.same(trace_id, v.traceId)
    end
  end)
end)
end
