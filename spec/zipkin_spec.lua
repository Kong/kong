local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex

local fmt = string.format

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
  return to_hex(utils.get_rand_bytes(16))
end


local function gen_span_id()
  return to_hex(utils.get_rand_bytes(8))
end


for _, strategy in helpers.each_strategy() do
describe("http integration tests with zipkin server [#" .. strategy .. "]", function()
  local proxy_client_grpc
  local tcp_service
  local route, grpc_route, tcp_route
  local zipkin_client
  local proxy_client

  local function wait_for_spans(trace_id, number_of_spans)
    local spans = {}
    helpers.wait_until(function()
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == number_of_spans
    end)
    return utils.unpack(spans)
  end

  local function wait_for_stream_spans(remoteServiceName, number_of_spans)
    local spans = {}
    helpers.wait_until(function()
      local res = zipkin_client:get("/api/v2/traces", {
        query = {
          limit = 10,
          remoteServiceName = remoteServiceName,
        }
      })
      local all_spans = cjson.decode(assert.response(res).has.status(200))
      if #all_spans > 0 then
        spans = all_spans[1]
        return #spans == number_of_spans
      end
    end)
    return utils.unpack(spans)
  end

  -- the following assertions should be true on any span list, even in error mode
  local function assert_span_invariants(request_span, proxy_span, expected_name, trace_id)
    -- request_span
    assert.same("table", type(request_span))
    assert.same("string", type(request_span.id))
    assert.same(expected_name, request_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("SERVER", request_span.kind)

    assert.same("string", type(request_span.traceId))
    assert.equals(trace_id, request_span.traceId)
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
    assert.equals(trace_id, proxy_span.traceId)
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


  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      -- enable on TCP as well (by default it is only enabled on http, https, grpc, grpcs)
      protocols = { "http", "https", "tcp", "tls", "grpc", "grpcs" },
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

    -- tcp upstream
    tcp_service = bp.services:insert({
      name = string.lower("tcp-" .. utils.random_string()),
      protocol = "tcp",
      host = helpers.mock_upstream_host,
      port = helpers.mock_upstream_stream_port,
    })

    tcp_route = bp.routes:insert {
      destinations = { { port = 19000 } },
      protocols = { "tcp" },
      service = tcp_service,
    }

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      stream_listen = helpers.get_proxy_ip(false) .. ":19000",
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

    local balancer_span, proxy_span, request_span = wait_for_spans(trace_id, 3)
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get", trace_id)

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

    local balancer_span, proxy_span, request_span = wait_for_spans(trace_id, 3)
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "post", trace_id)

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

  it("generates spans, tags and annotations for regular #stream requests", function()
    local tcp = ngx.socket.tcp()
    assert(tcp:connect(helpers.get_proxy_ip(false), 19000))

    assert(tcp:send("hello\n"))

    local body = assert(tcp:receive("*a"))
    assert.equal("hello\n", body)

    assert(tcp:close())

    local balancer_span, proxy_span, request_span = wait_for_stream_spans(tcp_service.name, 3)

    -- request span
    assert.same("table", type(request_span))
    assert.same("string", type(request_span.id))
    assert.same("stream", request_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("SERVER", request_span.kind)

    assert.same("string", type(request_span.traceId))
    assert_is_integer(request_span.timestamp)

    if request_span.duration and proxy_span.duration then
      assert.truthy(request_span.duration >= proxy_span.duration)
    end

    assert.is_nil(request_span.annotations)
    assert.same({ serviceName = "kong" }, request_span.localEndpoint)

    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({ lc = "kong" }, request_tags)
    local consumer_port = request_span.remoteEndpoint.port
    assert_is_integer(consumer_port)
    assert.same({
      ipv4 = "127.0.0.1",
      port = consumer_port,
    }, request_span.remoteEndpoint)

    -- proxy span
    assert.same("table", type(proxy_span))
    assert.same("string", type(proxy_span.id))
    assert.same(request_span.name .. " (proxy)", proxy_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("CLIENT", proxy_span.kind)

    assert.same("string", type(proxy_span.traceId))
    assert_is_integer(proxy_span.timestamp)

    if proxy_span.duration then
      assert.truthy(proxy_span.duration >= 0)
    end

    assert.equals(2, #proxy_span.annotations)
    local pann = annotations_to_hash(proxy_span.annotations)

    assert_is_integer(pann["kps"])
    assert_is_integer(pann["kpf"])

    assert.truthy(pann["kps"] <= pann["kpf"])
    assert.same({
      ["kong.route"] = tcp_route.id,
      ["kong.service"] = tcp_service.id,
      ["peer.hostname"] = "127.0.0.1",
    }, proxy_span.tags)

    assert.same({
      ipv4 = helpers.mock_upstream_host,
      port = helpers.mock_upstream_stream_port,
      serviceName = tcp_service.name,
    }, proxy_span.remoteEndpoint)

    -- specific assertions for balancer_span
    assert.equals(balancer_span.parentId, request_span.id)
    assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
    assert.equals("number", type(balancer_span.timestamp))
    if balancer_span.duration then
      assert.equals("number", type(balancer_span.duration))
    end

    assert.same({
      ipv4 = helpers.mock_upstream_host,
      port = helpers.mock_upstream_stream_port,
      serviceName = tcp_service.name,
    }, balancer_span.remoteEndpoint)
    assert.same({ serviceName = "kong" }, balancer_span.localEndpoint)
    assert.same({
      ["kong.balancer.try"] = "1",
      ["kong.route"] = tcp_route.id,
      ["kong.service"] = tcp_service.id,
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

    local proxy_span, request_span = wait_for_spans(trace_id, 2)

    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get", trace_id)

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

    local proxy_span, request_span = wait_for_spans(trace_id, 2)

    assert.equals(trace_id, proxy_span.traceId)
    assert.equals(trace_id, request_span.traceId)
  end)


  describe("b3 single header propagation", function()
    it("works on regular calls", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()
      local parent_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id),
          host = "mock-http-route",
        },
      })
      assert.response(r).has.status(200)

      local balancer_span, proxy_span, request_span = wait_for_spans(trace_id, 3)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(span_id, request_span.id)
      assert.equals(parent_id, request_span.parentId)

      assert.equals(trace_id, proxy_span.traceId)
      assert.not_equals(span_id, proxy_span.id)
      assert.equals(span_id, proxy_span.parentId)

      assert.equals(trace_id, balancer_span.traceId)
      assert.not_equals(span_id, balancer_span.id)
      assert.equals(span_id, balancer_span.parentId)
    end)

    it("works without parent_id", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id),
          host = "mock-http-route",
        },
      })
      assert.response(r).has.status(200)

      local balancer_span, proxy_span, request_span = wait_for_spans(trace_id, 3)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(span_id, request_span.id)

      assert.equals(trace_id, proxy_span.traceId)
      assert.not_equals(span_id, proxy_span.id)
      assert.equals(span_id, proxy_span.parentId)

      assert.equals(trace_id, balancer_span.traceId)
      assert.not_equals(span_id, balancer_span.id)
      assert.equals(span_id, balancer_span.parentId)
    end)

    it("works with only trace_id and span_id", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s", trace_id, span_id),
          ["x-b3-sampled"] = "1",
          host = "mock-http-route",
        },
      })
      assert.response(r).has.status(200)

      local balancer_span, proxy_span, request_span = wait_for_spans(trace_id, 3)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(span_id, request_span.id)

      assert.equals(trace_id, proxy_span.traceId)
      assert.not_equals(span_id, proxy_span.id)
      assert.equals(span_id, proxy_span.parentId)

      assert.equals(trace_id, balancer_span.traceId)
      assert.not_equals(span_id, balancer_span.id)
      assert.equals(span_id, balancer_span.parentId)
    end)

    it("works on non-matched requests", function()
      local trace_id = gen_trace_id()
      local span_id = gen_span_id()

      local r = proxy_client:get("/foobar", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id)
        },
      })
      assert.response(r).has.status(404)

      local proxy_span, request_span = wait_for_spans(trace_id, 2)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(span_id, request_span.id)

      assert.equals(trace_id, proxy_span.traceId)
      assert.not_equals(span_id, proxy_span.id)
      assert.equals(span_id, proxy_span.parentId)
    end)
  end)
end)
end
