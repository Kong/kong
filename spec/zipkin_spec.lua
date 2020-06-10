local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local to_hex = require "resty.string".to_hex

local fmt = string.format

local ZIPKIN_HOST = "zipkin"
local ZIPKIN_PORT = 9411
local GRPCBIN_HOST = "grpcbin"
local GRPCBIN_PORT = 9000

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


local function gen_trace_id(traceid_byte_count)
  return to_hex(utils.get_rand_bytes(traceid_byte_count))
end


local function gen_span_id()
  return to_hex(utils.get_rand_bytes(8))
end

-- assumption: tests take less than this (usually they run in ~2 seconds)
local MAX_TIMESTAMP_AGE = 5 * 60 -- 5 minutes
local function assert_valid_timestamp(timestamp_mu, start_s)
  assert_is_integer(timestamp_mu)
  local age_s = timestamp_mu / 1000000 - start_s

  if age_s < 0 or age_s > MAX_TIMESTAMP_AGE then
    error("out of bounds timestamp: " .. timestamp_mu .. "mu (age: " .. age_s .. "s)")
  end
end

local function wait_for_spans(zipkin_client, number_of_spans, remoteServiceName, trace_id)
  local spans = {}
  helpers.wait_until(function()
    if trace_id then
      local res = assert(zipkin_client:get("/api/v2/trace/" .. trace_id))
      spans = cjson.decode(assert.response(res).has.status(200))
      return #spans == number_of_spans
    end

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


for _, strategy in helpers.each_strategy() do
for _, traceid_byte_count in ipairs({ 8, 16 }) do
describe("http integration tests with zipkin server [#"
         .. strategy .. "] traceid_byte_count: "
         .. traceid_byte_count, function()

  local proxy_client_grpc
  local service, grpc_service, tcp_service
  local route, grpc_route, tcp_route
  local zipkin_client
  local proxy_client

  -- the following assertions should be true on any span list, even in error mode
  local function assert_span_invariants(request_span, proxy_span, expected_name, traceid_len, start_s)
    -- request_span
    assert.same("table", type(request_span))
    assert.same("string", type(request_span.id))
    assert.same(expected_name, request_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("SERVER", request_span.kind)

    assert.same("string", type(request_span.traceId))
    assert.equals(traceid_len, #request_span.traceId, request_span.traceId)
    assert_valid_timestamp(request_span.timestamp, start_s)

    if request_span.duration and proxy_span.duration then
      assert.truthy(request_span.duration >= proxy_span.duration)
    end

    assert.equals(2, #request_span.annotations)
    local rann = annotations_to_hash(request_span.annotations)
    assert_valid_timestamp(rann["krs"], start_s)
    assert_valid_timestamp(rann["krf"], start_s)
    assert.truthy(rann["krs"] <= rann["krf"])

    assert.same({ serviceName = "kong" }, request_span.localEndpoint)

    -- proxy_span
    assert.same("table", type(proxy_span))
    assert.same("string", type(proxy_span.id))
    assert.same(request_span.name .. " (proxy)", proxy_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("CLIENT", proxy_span.kind)

    assert.same("string", type(proxy_span.traceId))
    assert.equals(request_span.traceId, proxy_span.traceId)
    assert_valid_timestamp(proxy_span.timestamp, start_s)

    if request_span.duration and proxy_span.duration then
      assert.truthy(proxy_span.duration >= 0)
    end

    assert.equals(6, #proxy_span.annotations)
    local pann = annotations_to_hash(proxy_span.annotations)

    assert_valid_timestamp(pann["kas"], start_s)
    assert_valid_timestamp(pann["kaf"], start_s)
    assert_valid_timestamp(pann["khs"], start_s)
    assert_valid_timestamp(pann["khf"], start_s)
    assert_valid_timestamp(pann["kbs"], start_s)
    assert_valid_timestamp(pann["kbf"], start_s)

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
        http_endpoint = fmt("http://%s:%d/api/v2/spans", ZIPKIN_HOST, ZIPKIN_PORT),
        traceid_byte_count = traceid_byte_count,
        static_tags = {
          { name = "static", value = "ok" },
        }
      }
    })

    service = bp.services:insert {
      name = string.lower("http-" .. utils.random_string()),
    }

    -- kong (http) mock upstream
    route = bp.routes:insert({
      service = service,
      hosts = { "http-route" },
      preserve_host = true,
    })

    -- grpc upstream
    grpc_service = bp.services:insert {
      name = string.lower("grpc-" .. utils.random_string()),
      url = fmt("grpc://%s:%d", GRPCBIN_HOST, GRPCBIN_PORT),
    }

    grpc_route = bp.routes:insert {
      service = grpc_service,
      protocols = { "grpc" },
      hosts = { "grpc-route" },
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
    zipkin_client = helpers.http_client(ZIPKIN_HOST, ZIPKIN_PORT)
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("generates spans, tags and annotations for regular requests", function()
    local start_s = ngx.now()

    local r = proxy_client:get("/", {
      headers = {
        ["x-b3-sampled"] = "1",
        host  = "http-route",
      },
    })
    assert.response(r).has.status(200)

    local balancer_span, proxy_span, request_span =
      wait_for_spans(zipkin_client, 3, service.name)
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get", traceid_byte_count * 2, start_s)

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({
      ["http.method"] = "GET",
      ["http.path"] = "/",
      ["http.status_code"] = "200", -- found (matches server status)
      lc = "kong",
      static = "ok",
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
      serviceName = service.name,
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
      serviceName = service.name,
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
    local start_s = ngx.now()

    local ok, resp = proxy_client_grpc({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-H"] = "'x-b3-sampled: 1'",
        ["-authority"] = "grpc-route",
      }
    })
    assert(ok, resp)
    assert.truthy(resp)

    local balancer_span, proxy_span, request_span =
      wait_for_spans(zipkin_client, 3, grpc_service.name)
    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "post", traceid_byte_count * 2, start_s)

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil

    assert.same({
      ["http.method"] = "POST",
      ["http.path"] = "/hello.HelloService/SayHello",
      ["http.status_code"] = "200", -- found (matches server status)
      lc = "kong",
      static = "ok",
    }, request_tags)
    local consumer_port = request_span.remoteEndpoint.port
    assert_is_integer(consumer_port)
    assert.same({
      ipv4 = '127.0.0.1',
      port = consumer_port,
    }, request_span.remoteEndpoint)

    -- specific assertions for proxy_span
    assert.same(proxy_span.tags["kong.route"], grpc_route.id)
    assert.same(proxy_span.tags["peer.hostname"], GRPCBIN_HOST)

    -- random ip assigned by Docker to the grpcbin container
    local grpcbin_ip = proxy_span.remoteEndpoint.ipv4
    assert.same({
      ipv4 = grpcbin_ip,
      port = GRPCBIN_PORT,
      serviceName = grpc_service.name,
    },
    proxy_span.remoteEndpoint)

    -- specific assertions for balancer_span
    assert.equals(balancer_span.parentId, request_span.id)
    assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
    assert_valid_timestamp(balancer_span.timestamp, start_s)

    if balancer_span.duration then
      assert_is_integer(balancer_span.duration)
    end

    assert.same({
      ipv4 = grpcbin_ip,
      port = GRPCBIN_PORT,
      serviceName = grpc_service.name,
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
    local start_s = ngx.now()
    local tcp = ngx.socket.tcp()
    assert(tcp:connect(helpers.get_proxy_ip(false), 19000))

    assert(tcp:send("hello\n"))

    local body = assert(tcp:receive("*a"))
    assert.equal("hello\n", body)

    assert(tcp:close())

    local balancer_span, proxy_span, request_span =
      wait_for_spans(zipkin_client, 3, tcp_service.name)

    -- request span
    assert.same("table", type(request_span))
    assert.same("string", type(request_span.id))
    assert.same("stream", request_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("SERVER", request_span.kind)

    assert.same("string", type(request_span.traceId))
    assert_valid_timestamp(request_span.timestamp, start_s)

    if request_span.duration and proxy_span.duration then
      assert.truthy(request_span.duration >= proxy_span.duration)
    end

    assert.is_nil(request_span.annotations)
    assert.same({ serviceName = "kong" }, request_span.localEndpoint)

    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({
      lc = "kong",
      static = "ok",
    }, request_tags)
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
    assert_valid_timestamp(proxy_span.timestamp, start_s)

    if proxy_span.duration then
      assert.truthy(proxy_span.duration >= 0)
    end

    assert.equals(2, #proxy_span.annotations)
    local pann = annotations_to_hash(proxy_span.annotations)

    assert_valid_timestamp(pann["kps"], start_s)
    assert_valid_timestamp(pann["kpf"], start_s)

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
    local trace_id = gen_trace_id(traceid_byte_count)
    local start_s = ngx.now()

    local r = assert(proxy_client:send {
      method  = "GET",
      path    = "/foobar",
      headers = {
        ["x-b3-traceid"] = trace_id,
        ["x-b3-sampled"] = "1",
      },
    })
    assert.response(r).has.status(404)

    local proxy_span, request_span =
      wait_for_spans(zipkin_client, 2, nil, trace_id)

    -- common assertions for request_span and proxy_span
    assert_span_invariants(request_span, proxy_span, "get", #trace_id, start_s)

    -- specific assertions for request_span
    local request_tags = request_span.tags
    assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
    request_tags["kong.node.id"] = nil
    assert.same({
      ["http.method"] = "GET",
      ["http.path"] = "/foobar",
      ["http.status_code"] = "404", -- note that this was "not found"
      lc = "kong",
      static = "ok",
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
    local trace_id = gen_trace_id(traceid_byte_count)

    local r = assert(proxy_client:send {
      method  = "GET",
      path    = "/foobar",
      headers = {
        ["x-b3-traceid"] = trace_id,
        ["x-b3-sampled"] = "1",
      },
    })
    assert.response(r).has.status(404)

    local proxy_span, request_span =
      wait_for_spans(zipkin_client, 2, nil, trace_id)

    assert.equals(trace_id, proxy_span.traceId)
    assert.equals(trace_id, request_span.traceId)
  end)


  describe("b3 single header propagation", function()
    it("works on regular calls", function()
      local trace_id = gen_trace_id(traceid_byte_count)
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

      local balancer_span, proxy_span, request_span =
        wait_for_spans(zipkin_client, 3, nil, trace_id)

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
      local trace_id = gen_trace_id(traceid_byte_count)
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1%-%x+", json.headers.b3)

      local balancer_span, proxy_span, request_span =
        wait_for_spans(zipkin_client, 3, nil, trace_id)

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
      local trace_id = gen_trace_id(traceid_byte_count)
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s", trace_id, span_id),
          ["x-b3-sampled"] = "1",
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1%-%x+", json.headers.b3)

      local balancer_span, proxy_span, request_span =
        wait_for_spans(zipkin_client, 3, nil, trace_id)

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
      local trace_id = gen_trace_id(traceid_byte_count)
      local span_id = gen_span_id()

      local r = proxy_client:get("/foobar", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id)
        },
      })
      assert.response(r).has.status(404)

      local proxy_span, request_span =
        wait_for_spans(zipkin_client, 2, nil, trace_id)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(span_id, request_span.id)

      assert.equals(trace_id, proxy_span.traceId)
      assert.not_equals(span_id, proxy_span.id)
      assert.equals(span_id, proxy_span.parentId)
    end)
  end)


  describe("w3c traceparent header propagation", function()
    it("works on regular calls", function()
      local trace_id = gen_trace_id(16) -- w3c only admits 16-byte trace_ids
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

      local balancer_span, proxy_span, request_span =
        wait_for_spans(zipkin_client, 3, nil, trace_id)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(parent_id, request_span.parentId)

      assert.equals(trace_id, proxy_span.traceId)
      assert.equals(trace_id, balancer_span.traceId)
    end)

    it("works on non-matched requests", function()
      local trace_id = gen_trace_id(16) -- w3c only admits 16-bit trace_ids
      local parent_id = gen_span_id()

      local r = proxy_client:get("/foobar", {
        headers = {
          traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        },
      })
      assert.response(r).has.status(404)

      local proxy_span, request_span =
        wait_for_spans(zipkin_client, 2, nil, trace_id)

      assert.equals(trace_id, request_span.traceId)
      assert.equals(parent_id, request_span.parentId)

      assert.equals(trace_id, proxy_span.traceId)
    end)
  end)
end)
end
end
