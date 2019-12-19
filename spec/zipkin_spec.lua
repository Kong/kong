local TEST_TIMEOUT = 2

local cqueues = require "cqueues"
local helpers = require "spec.helpers"
local http_request = require "http.request"
local http_server = require "http.server"
local new_headers = require "http.headers".new
local cjson = require "cjson"

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



for _, strategy in helpers.each_strategy() do
describe("integration tests with mock zipkin server [#" .. strategy .. "]", function()
  local server

  local cb
  local proxy_port, proxy_host
  local zipkin_port, zipkin_host
  local proxy_client_grpc
  local route, grpc_route

  after_each(function()
    cb = nil
  end)

  local with_server do
    local function assert_loop(cq, timeout)
      local ok, err, _, thd = cq:loop(timeout)
      if not ok then
        if thd then
          err = debug.traceback(thd, err)
        end
        error(err, 2)
      end
    end

    with_server = function(server_cb, client_cb)
      cb = spy.new(server_cb)
      local cq = cqueues.new()
      cq:wrap(assert_loop, server)
      cq:wrap(client_cb)
      assert_loop(cq, TEST_TIMEOUT)
      return (cb:called())
    end
  end


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
    assert.truthy(request_span.duration >= proxy_span.duration)

    assert.equals(2, #request_span.annotations)
    local rann = annotations_to_hash(request_span.annotations)
    assert_is_integer(rann["krs"])
    assert_is_integer(rann["krf"])
    assert.truthy(rann["krs"] <= rann["krf"])

    assert.same(ngx.null, request_span.localEndpoint)

    -- proxy_span
    assert.same("table", type(proxy_span))
    assert.same("string", type(proxy_span.id))
    assert.same(request_span.name .. " (proxy)", proxy_span.name)
    assert.same(request_span.id, proxy_span.parentId)

    assert.same("CLIENT", proxy_span.kind)

    assert.same("string", type(proxy_span.traceId))
    assert.truthy(proxy_span.traceId:match("^%x+$"))
    assert_is_integer(proxy_span.timestamp)
    assert.truthy(proxy_span.duration >= 0)

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
    -- create a mock zipkin server
    server = assert(http_server.listen {
      host = "127.0.0.1",
      port = 0,
      onstream = function(_, stream)
        local req_headers = assert(stream:get_headers())
        local res_headers = new_headers()
        res_headers:upsert(":status", "500")
        res_headers:upsert("connection", "close")
        assert(cb, "test has not set callback")
        local body = cb(req_headers, res_headers, stream)
        assert(stream:write_headers(res_headers, false))
        assert(stream:write_chunk(body or "", true))
      end,
    })
    assert(server:listen())
    local _
    _, zipkin_host, zipkin_port = server:localname()

    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      config = {
        sample_ratio = 1,
        http_endpoint = string.format("http://%s:%d/api/v2/spans", zipkin_host, zipkin_port),
      }
    })

    -- kong (http) mock upstream
    route = bp.routes:insert({
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

    proxy_host = helpers.get_proxy_ip(false)
    proxy_port = helpers.get_proxy_port(false)
    proxy_client_grpc = helpers.proxy_client_grpc()
  end)

  teardown(function()
    server:close()
    helpers.stop_kong()
  end)

  it("generates spans, tags and annotations for regular requests", function()
    assert.truthy(with_server(function(_, _, stream)
      local spans = cjson.decode((assert(stream:get_body_as_string())))

      assert.equals(3, #spans)
      local balancer_span, proxy_span, request_span = spans[1], spans[2], spans[3]
      -- common assertions for request_span and proxy_span
      assert_span_invariants(request_span, proxy_span, "GET")

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
      local peer_port = request_span.remoteEndpoint.port
      assert_is_integer(peer_port)
      assert.same({ ipv4 = "127.0.0.1", port = peer_port }, request_span.remoteEndpoint)

      -- specific assertions for proxy_span
      assert.same(proxy_span.tags["kong.route"], route.id)
      assert.same(proxy_span.tags["peer.hostname"], "127.0.0.1")

      assert.same({ ipv4 = helpers.mock_upstream_host, port = helpers.mock_upstream_port },
        proxy_span.remoteEndpoint)

      -- specific assertions for balancer_span
      assert.equals(balancer_span.parentId, request_span.id)
      assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
      assert_is_integer(balancer_span.timestamp)
      assert_is_integer(balancer_span.duration)

      assert.same({ ipv4 = helpers.mock_upstream_host, port = helpers.mock_upstream_port },
        balancer_span.remoteEndpoint)
      assert.equals(ngx.null, balancer_span.localEndpoint)
      assert.same({
        error = "false",
        ["kong.balancer.try"] = "1",
      }, balancer_span.tags)
    end, function()
      -- regular request which matches the existing route
      local req = http_request.new_from_uri("http://mock-http-route/")
      req.host = proxy_host
      req.port = proxy_port
      assert(req:go())
    end))
  end)

  it("generates spans, tags and annotations for regular requests (#grpc)", function()
    assert.truthy(with_server(function(_, _, stream)
      local spans = cjson.decode((assert(stream:get_body_as_string())))

      --assert.equals(3, #spans)
      local balancer_span, proxy_span, request_span = spans[1], spans[2], spans[3]
      -- common assertions for request_span and proxy_span
      assert_span_invariants(request_span, proxy_span, "POST")

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
      local peer_port = request_span.remoteEndpoint.port
      assert_is_integer(peer_port)
      assert.same({ ipv4 = "127.0.0.1", port = peer_port }, request_span.remoteEndpoint)

      -- specific assertions for proxy_span
      assert.same(proxy_span.tags["kong.route"], grpc_route.id)
      assert.same(proxy_span.tags["peer.hostname"], "localhost")

      assert.same({ ipv4 = "127.0.0.1", port = 15002 },
        proxy_span.remoteEndpoint)

      -- specific assertions for balancer_span
      assert.equals(balancer_span.parentId, request_span.id)
      assert.equals(request_span.name .. " (balancer try 1)", balancer_span.name)
      assert_is_integer(balancer_span.timestamp)
      assert_is_integer(balancer_span.duration)

      assert.same({ ipv4 = "127.0.0.1", port = 15002 },
        balancer_span.remoteEndpoint)
      assert.equals(ngx.null, balancer_span.localEndpoint)
      assert.same({
        error = "false",
        ["kong.balancer.try"] = "1",
      }, balancer_span.tags)
    end, function()
      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "mock-grpc-route",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)
    end))
  end)

  it("generates spans, tags and annotations for non-matched requests", function()
    assert.truthy(with_server(function(_, _, stream)
      local spans = cjson.decode((assert(stream:get_body_as_string())))
      assert.equals(2, #spans)
      local proxy_span, request_span = spans[1], spans[2]
      -- common assertions for request_span and proxy_span
      assert_span_invariants(request_span, proxy_span, "GET")

      -- specific assertions for request_span
      local request_tags = request_span.tags
      assert.truthy(request_tags["kong.node.id"]:match("^[%x-]+$"))
      request_tags["kong.node.id"] = nil
      assert.same({
        ["http.method"] = "GET",
        ["http.path"] = "/",
        ["http.status_code"] = "404", -- note that this was "not found"
        lc = "kong"
      }, request_tags)
      local peer_port = request_span.remoteEndpoint.port
      assert_is_integer(peer_port)
      assert.same({ ipv4 = "127.0.0.1", port = peer_port }, request_span.remoteEndpoint)

      -- specific assertions for proxy_span
      assert.is_nil(proxy_span.tags)

      assert.equals(ngx.null, proxy_span.remoteEndpoint)
      assert.equals(ngx.null, proxy_span.localEndpoint)
    end, function()
      -- This request reaches the proxy, but doesn't match any route.
      -- The plugin runs in "error mode": access phase doesn't run, but others, like header_filter, do run
      local uri = string.format("http://%s:%d/", proxy_host, proxy_port)
      local req = http_request.new_from_uri(uri)
      assert(req:go())
    end))
  end)

  it("propagates b3 headers on routed request", function()
    local trace_id = "1234567890abcdef"
    assert.truthy(with_server(function(_, _, stream)
      local spans = cjson.decode((assert(stream:get_body_as_string())))
      for _, v in ipairs(spans) do
        assert.same(trace_id, v.traceId)
      end
    end, function()
      -- regular request, with extra headers
      local req = http_request.new_from_uri("http://mock-http-route/")
      req.host = proxy_host
      req.port = proxy_port
      req.headers:upsert("x-b3-traceid", trace_id)
      req.headers:upsert("x-b3-sampled", "1")
      assert(req:go())
    end))
  end)

  -- TODO add grpc counterpart of above test case

  it("propagates b3 headers for non-matched requests", function()
    local trace_id = "1234567890abcdef"
    assert.truthy(with_server(function(_, _, stream)
      local spans = cjson.decode((assert(stream:get_body_as_string())))
      for _, v in ipairs(spans) do
        assert.same(trace_id, v.traceId)
      end
    end, function()
      -- This request reaches the proxy, but doesn't match any route. The trace_id should be respected here too
      local uri = string.format("http://%s:%d/", proxy_host, proxy_port)
      local req = http_request.new_from_uri(uri)
      req.headers:upsert("x-b3-traceid", trace_id)
      req.headers:upsert("x-b3-sampled", "1")
      assert(req:go())
    end))
  end)
end)
end
