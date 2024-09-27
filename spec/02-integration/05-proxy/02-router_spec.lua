local admin_api = require "spec.fixtures.admin_api"
local helpers = require "spec.helpers"
local cjson   = require "cjson"
local path_handling_tests = require "spec.fixtures.router_path_handling_tests"
local table_insert = table.insert

local tonumber = tonumber

local enable_buffering
local enable_buffering_plugin
local stream_tls_listen_port = 9020


local function insert_routes(bp, routes)
  if type(bp) ~= "table" then
    return error("expected arg #1 to be a table", 2)
  end
  if type(routes) ~= "table" then
    return error("expected arg #2 to be a table", 2)
  end

  if not bp.done then -- strategy ~= "off"
    bp = admin_api
  end

  enable_buffering_plugin = bp.plugins:insert({
    name = "enable-buffering",
    protocols = { "http", "https", "grpc", "grpcs" },
    service = ngx.null,
    consumer = ngx.null,
    route = ngx.null,
  })

  for i = 1, #routes do
    local route = routes[i]

    local service
    if route.service == ngx.null then
      service = route.service

    else
      service = route.service or {}

      if not service.host then
        service.host = helpers.mock_upstream_host
      end

      if not service.port then
        service.port = helpers.mock_upstream_port
      end

      if not service.protocol then
        service.protocol = helpers.mock_upstream_protocol
      end

      service = bp.named_services:insert(service)
    end
    route.service = service

    if not route.protocols then
      route.protocols = { "http" }
    end

    route.service = service
    route = bp.routes:insert(route)
    route.service = service

    routes[i] = route
  end

  if bp.done then
    local declarative = require "kong.db.declarative"

    local cfg = bp.done()
    local yaml = declarative.to_yaml_string(cfg)
    local admin_client = helpers.admin_client()

    local res = assert(admin_client:send {
      method  = "POST",
      path    = "/config",
      body    = {
        config = yaml,
      },
      headers = {
        ["Content-Type"] = "multipart/form-data",
      }
    })
    assert.res_status(201, res)
    admin_client:close()

  end

  ngx.sleep(0.5)  -- temporary wait for worker events and timers

  return routes
end

local function remove_routes(strategy, routes)
  if strategy == "off" or not routes then
    return
  end

  local services = {}

  for _, route in ipairs(routes) do
    if route.service ~= ngx.null then
      local sid = route.service.id
      if not services[sid] then
        services[sid] = route.service
        table.insert(services, services[sid])
      end
    end
  end

  for _, route in ipairs(routes) do
    admin_api.routes:remove({ id = route.id })
  end

  for _, service in ipairs(services) do
    admin_api.services:remove(service)
  end

  admin_api.plugins:remove(enable_buffering_plugin)
end

for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, b in ipairs({ false, true }) do enable_buffering = b
for _, strategy in helpers.each_strategy() do
  describe("Router [#" .. strategy .. ", flavor = " .. flavor .. "] with buffering [" .. (b and "on]" or "off]") , function()
    local proxy_client
    local proxy_ssl_client
    local bp
    local it_trad_only = (flavor == "traditional") and it or pending

    lazy_setup(function()
      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }
      fixtures.dns_mock:A {
        name = "grpcs_1.test",
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = "grpcs_2.test",
        address = "127.0.0.1",
      }

      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "enable-buffering",
      })

      assert(helpers.start_kong({
        router_flavor = flavor,
        database = strategy,
        plugins = "bundled,enable-buffering",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        stream_listen = string.format("127.0.0.1:%d ssl", stream_tls_listen_port),
        allow_debug_header = true,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
      if proxy_ssl_client then
        proxy_ssl_client:close()
      end
    end)

    describe("no routes match", function()

      it("responds 404 if no route matches", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            host  = "inexistent.com"
          }
        })

        local body = assert.response(res).has_status(404)
        local json = cjson.decode(body)
        assert.matches("^kong/", res.headers.server)
        assert.equal("no Route matched with those values", json.message)
      end)
    end)

    describe("use-cases", function()
      local routes
      local first_service_name

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            methods    = { "GET" },
            protocols  = { "http" },
            strip_path = false,
          },
          {
            methods    = { "POST", "PUT" },
            paths      = { "/post", "/put" },
            protocols  = { "http" },
            strip_path = false,
          },
          {
            paths      = { "/mock_upstream" },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/status",
            },
          },
          {
            paths      = { "/private" },
            protocols  = { "http" },
            strip_path = false,
            service    = {
              path     = "/basic-auth/",
            },
          },
          {
            paths      = { [[~/users/\d+/profile]] },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/anything",
            },
          },
          {
            protocols = { "http", "https" },
            hosts     = { "serviceless-route-http.test" },
            service   = ngx.null,
          },
          {
            paths      = { "/disabled-service1" },
            protocols  = { "http" },
            strip_path = false,
            service    = {
              path     = "/disabled-service-path/",
              enabled  = false,
            },
          },
          {
            paths      = { [[~/enabled-service/\w+]] },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/anything/",
              enabled  = true,
              name     = "enabled-service",
            },
          },
          {
            paths     = { "/enabled-service/disabled" },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/some-path/",
              enabled  = false,
            },
          },
        })
        first_service_name = routes[1].service.name
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("responds 503 if no service found", function()
        local res, body
        helpers.wait_until(function()
          res = assert(proxy_client:get("/", {
            headers = {
              Host = "serviceless-route-http.test",
            },
          }))
          return pcall(function()
            body = assert.response(res).has_status(503)
          end)
        end, 10)

        local json = cjson.decode(body)
        assert.equal("no Service found with those values", json.message)

        local res = assert(proxy_ssl_client:get("/", {
          headers = {
            Host = "serviceless-route-http.test",
          },
        }))
        local body = assert.response(res).has_status(503)
        local json = cjson.decode(body)

        assert.equal("no Service found with those values", json.message)
      end)

      it("restricts an route to its methods if specified", function()
        -- < HTTP/1.1 POST /post
        -- > 200 OK
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          headers = { ["kong-debug"] = 1 },
        })

        assert.response(res).has_status(200)
        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])

        -- < HTTP/1.1 DELETE /post
        -- > 404 NOT FOUND
        res = assert(proxy_client:send {
          method  = "DELETE",
          path    = "/post",
          headers = { ["kong-debug"] = 1 },
        })

        assert.response(res).has_status(404)
        assert.is_nil(res.headers["kong-route-id"])
        assert.is_nil(res.headers["kong-service-id"])
        assert.is_nil(res.headers["kong-service-name"])
      end)

      it("routes by method-only if no other match is found", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["kong-debug"] = 1 },
        })

        assert.response(res).has_status(200)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
      end)

      describe("requests without Host header", function()
        it("HTTP/1.0 routes normally", function()
          -- a very limited HTTP client for sending requests without Host
          -- header
          local sock = ngx.socket.tcp()

          finally(function()
            sock:close()
          end)

          assert(sock:connect(helpers.get_proxy_ip(),
                              helpers.get_proxy_port()))

          local req = "GET /get HTTP/1.0\r\nKong-Debug: 1\r\n\r\n"
          assert(sock:send(req))

          local line = assert(sock:receive("*l"))

          local status = tonumber(string.sub(line, 10, 12))
          assert.equal(200, status)

          -- TEST: we matched an API that had no Host header defined
          local remainder = assert(sock:receive("*a"))
          assert.matches("kong-service-name: " .. first_service_name,
                         string.lower(remainder), nil, true)
        end)

        it("HTTP/1.1 is rejected by NGINX", function()
          local sock = ngx.socket.tcp()

          finally(function()
            sock:close()
          end)

          assert(sock:connect(helpers.get_proxy_ip(),
                              helpers.get_proxy_port()))

          local req = "GET /get HTTP/1.1\r\nKong-Debug: 1\r\n\r\n"
          assert(sock:send(req))

          -- TEST: NGINX rejected this request
          local line = assert(sock:receive("*l"))
          local status = tonumber(string.sub(line, 10, 12))
          assert.equal(400, status)

          -- TEST: we ensure that Kong catches this error and
          -- produces the response from its own error handler
          local remainder = assert(sock:receive("*a"))
          assert.matches("Bad request", remainder, nil, true)
          assert.matches("Server: kong/", remainder, nil, true)
        end)
      end)

      describe("route with a path component in its upstream_url", function()
        it("with strip_path = true", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/mock_upstream/201",
            headers = { ["kong-debug"] = 1 },
          })

          assert.res_status(201, res)

          assert.equal(routes[3].id,           res.headers["kong-route-id"])
          assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
          assert.equal(routes[3].service.name, res.headers["kong-service-name"])
        end)
      end)

      it("route with a path component in its upstream_url and strip_path = false", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/private/passwd",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(401, res)

        assert.equal(routes[4].id,           res.headers["kong-route-id"])
        assert.equal(routes[4].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[4].service.name, res.headers["kong-service-name"])
      end)

      it("route with a path component in its upstream_url and [uri] with a regex", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/users/foo/profile",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(404, res)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/users/123/profile",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(200, res)

        assert.equal(routes[5].id,           res.headers["kong-route-id"])
        assert.equal(routes[5].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[5].service.name, res.headers["kong-service-name"])
      end)

      describe('handles not enabled services', function()
        it('ignores route where service enabled=false', function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/disabled-service1",
            headers = { ["kong-debug"] = 1 },
          })

          assert.res_status(404, res)
        end)

        it('routes to regex path when longer path service enabled=false', function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/enabled-service/disabled",
            headers = { ["kong-debug"] = 1 },
          })

          assert.res_status(200, res)
          assert.equal(routes[8].id,           res.headers["kong-route-id"])
          assert.equal(routes[8].service.id,   res.headers["kong-service-id"])
          assert.equal("enabled-service",      res.headers["kong-service-name"])
        end)
      end)
    end)

    if not enable_buffering then
    describe("use cases #grpc", function()
      local routes
      local service = {
        url = helpers.grpcbin_url,
      }

      local proxy_client_grpc
      local proxy_client_grpcs

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            protocols = { "grpc", "grpcs" },
            hosts = {
              "grpc1",
              "grpc1:" .. helpers.get_proxy_port(false, true),
              "grpc1:" .. helpers.get_proxy_port(true, true),
            },
            service = service,
          },
          {
            protocols = { "grpc", "grpcs" },
            hosts = {
              "grpc2",
              "grpc2:" .. helpers.get_proxy_port(false, true),
              "grpc2:" .. helpers.get_proxy_port(true, true),
            },
            service = service,
          },
          {
            protocols = { "grpc", "grpcs" },
            paths = { "/hello.HelloService/SayHello" },
            service = service,
          },
          {
            protocols = { "grpc", "grpcs" },
            paths = { "/hello.HelloService/LotsOfReplies" },
            service = service,
          },
          {
            protocols = { "grpc", "grpcs" },
            hosts = { "*.grpc.com" },
            service = service,
          },
          {
            protocols = { "grpc", "grpcs" },
            hosts     = { "serviceless-route-grpc.test" },
            service   = ngx.null,
          }
        })

        proxy_client_grpc = helpers.proxy_client_grpc()
        proxy_client_grpcs = helpers.proxy_client_grpcs()
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("responds 503 if no service found", function()
        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "serviceless-route-grpc.test",
          }
        })

        assert.falsy(ok)
        assert.equal("ERROR:\n  Code: Unavailable\n  Message: no Service found with those values\n", resp)

        local ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "serviceless-route-grpc.test",
          }
        })

        assert.falsy(ok)
        assert.equal("ERROR:\n  Code: Unavailable\n  Message: no Service found with those values\n", resp)
      end)


      it("restricts a route to its 'hosts' if specified", function()
        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "grpc1",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[1].id, resp, nil, true)

        ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "grpc2",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[2].id, resp, nil, true)
      end)

      it("restricts a route to its 'hosts' if specified (grpcs)", function()
        local ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "grpc1",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[1].id, resp, nil, true)

        ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "grpc2",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[2].id, resp, nil, true)
      end)

      it("restricts a route to its wildcard 'hosts' if specified", function()
        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "service1.grpc.com",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[5].id, resp, nil, true)
      end)

      it("restricts a route to its wildcard 'hosts' if specified (grpcs)", function()
        local ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
            ["-authority"] = "service1.grpc.com",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[5].id, resp, nil, true)
      end)

      it("restricts a route to its 'paths' if specified", function()
        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[3].id, resp, nil, true)

        ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.LotsOfReplies",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[4].id, resp, nil, true)
      end)

      it("restricts a route to its 'paths' if specified (grpcs)", function()
        local ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[3].id, resp, nil, true)

        ok, resp = proxy_client_grpcs({
          service = "hello.HelloService.LotsOfReplies",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-v"] = true,
            ["-H"] = "'kong-debug: 1'",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-route-id: " .. routes[4].id, resp, nil, true)
      end)
    end)
    end -- not enable_buffering

    describe("URI regexes order of evaluation with created_at", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            created_at = 1234567890,
            strip_path = true,
            paths      = { "~/status/(re)" },
            service    = {
              name     = "regex_1",
              path     = "/status/200",
            },
          },
          {
            created_at = 1234567891,
            strip_path = true,
            paths      = { "~/status/(r)" },
            service    = {
              name     = "regex_2",
              path     = "/status/200",
            },
          },
          {
            created_at = 1234567892,
            strip_path = true,
            paths      = { "/status" },
            service    = {
              name     = "regex_3",
              path     = "/status/200",
            },
          }
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it_trad_only("depends on created_at field", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/r",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/re",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
      end)
    end)

    describe("URI regexes order of evaluation with regex_priority", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {

          -- TEST 1 (regex_priority)

          {
            strip_path = true,
            paths      = { "~/status/(?P<foo>re)" },
            service    = {
              name     = "regex_1",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
          {
            strip_path = true,
            paths      = { "~/status/(re)" },
            service    = {
              name     = "regex_2",
              path     = "/status/200",
            },
            regex_priority = 4, -- shadows service which is created before and is shorter
          },

          -- TEST 2 (tie breaker by created_at)

          {
            created_at = 1234567890,
            strip_path = true,
            paths      = { "~/status/(ab)" },
            service    = {
              name     = "regex_3",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
          {
            created_at = 1234567891,
            strip_path = true,
            paths      = { "~/status/(ab)c?" },
            service    = {
              name     = "regex_4",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("depends on the regex_priority field", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/re",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("regex_2", res.headers["kong-service-name"])
      end)

      it_trad_only("depends on created_at if regex_priority is tie", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/ab",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("regex_3", res.headers["kong-service-name"])
      end)
    end)

    describe("URI arguments (querystring)", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            hosts = { "mock_upstream" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("preserves URI arguments", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          query   = {
            foo   = "bar",
            hello = "world",
          },
          headers = {
            ["Host"] = "mock_upstream",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("bar", json.uri_args.foo)
        assert.equal("world", json.uri_args.hello)
      end)

      it("does proxy an empty querystring if URI does not contain arguments", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?",
          headers = {
            ["Host"] = "mock_upstream",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("/request%?$", json.vars.request_uri)
      end)

      it("does proxy a querystring with an empty value", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get?hello",
          headers = {
            ["Host"] = "mock_upstream",
          },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("/get%?hello$", json.url)
      end)
    end)

    describe("URI normalization", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            paths      = { "/foo/bar" },
          },
          {
            strip_path = true,
            paths      = { "/hello" },
          },
          {
            strip_path = false,
            paths      = { "/anything/world" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("matches against normalized URI with \"..\"", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/a/../bar",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
        assert.equal("/foo/a/../bar", body.headers["x-forwarded-path"])
      end)

      it("matches against normalized URI with \"//\"", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo//bar",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
        assert.equal("/foo//bar", body.headers["x-forwarded-path"])
      end)

      it("matches against normalized URI with \"/./\"", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/./bar",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
        assert.equal("/foo/./bar", body.headers["x-forwarded-path"])
      end)

      it("matches against normalized URI with percent-encoded characters", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/h%65llo",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
        assert.equal("/h%65llo", body.headers["x-forwarded-path"])
      end)

      it("proxies normalized URI to upstream with strip_path = true", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/h%65llo/anything/a/../b",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
        assert.equal("/anything/b", body.vars.request_uri)
      end)

      it("proxies normalized URI to upstream with strip_path = false", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/anything/./a/../wor%6cd/a/../b",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[3].id,           res.headers["kong-route-id"])
        assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[3].service.name, res.headers["kong-service-name"])
        assert.equal("/anything/world/b", body.vars.request_uri)
      end)

      it("re-encode special characters in request uri when proxying to the upstream", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/anything/world/cat%20and%20dog",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.res_status(200, res)
        body = cjson.decode(body)

        assert.equal(routes[3].id,           res.headers["kong-route-id"])
        assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[3].service.name, res.headers["kong-service-name"])
        assert.equal("/anything/world/cat%20and%20dog", body.vars.request_uri)
      end)
    end)

    describe("strip_path", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            paths      = { "/x/y/z", "/z/y/x" },
            strip_path = true,
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      describe("= true", function()
        it("strips subsequent calls to an route with different [paths]", function()
          local res_uri_1 = assert(proxy_client:send {
            method = "GET",
            path   = "/x/y/z/get",
          })

          local body = assert.res_status(200, res_uri_1)
          local json = cjson.decode(body)
          assert.matches("/get", json.url, nil, true)
          assert.not_matches("/x/y/z/get", json.url, nil, true)

          local res_uri_2 = assert(proxy_client:send {
            method = "GET",
            path   = "/z/y/x/get",
          })

          body = assert.res_status(200, res_uri_2)
          json = cjson.decode(body)
          assert.matches("/get", json.url, nil, true)
          assert.not_matches("/z/y/x/get", json.url, nil, true)

          local res_2_uri_1 = assert(proxy_client:send {
            method = "GET",
            path   = "/x/y/z/get",
          })

          body = assert.res_status(200, res_2_uri_1)
          json = cjson.decode(body)
          assert.matches("/get", json.url, nil, true)
          assert.not_matches("/x/y/z/get", json.url, nil, true)

          local res_2_uri_2 = assert(proxy_client:send {
            method = "GET",
            path   = "/x/y/z/get",
          })

          body = assert.res_status(200, res_2_uri_2)
          json = cjson.decode(body)
          assert.matches("/get", json.url, nil, true)
          assert.not_matches("/x/y/z/get", json.url, nil, true)
        end)
      end)
    end)

    describe("preserve_host", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            preserve_host = true,
            hosts         = { "preserved.com", "preserved.com:123" },
            service       = {
              path        = "/request"
            },
          },
          {
            preserve_host = false,
            hosts         = { "discarded.com" },
            service       = {
              path        = "/request"
            },
          },
          {
            strip_path    = false,
            preserve_host = true,
            paths         = { "/request" },
          }
        })

      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      describe("x = false (default)", function()
        it("uses hostname from upstream_url", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["Host"] = "discarded.com" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.matches(helpers.mock_upstream_host,
                         json.headers.host, nil, true) -- not testing :port
        end)

        it("uses port value from upstream_url if not default", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["Host"] = "discarded.com" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.matches(":" .. helpers.mock_upstream_port,
                          json.headers.host, nil, true) -- not testing hostname
        end)
      end)

      describe("= true", function()
        it("forwards request Host", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = { ["Host"] = "preserved.com" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("preserved.com", json.headers.host)
        end)

        it_trad_only("forwards request Host:Port even if port is default", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["Host"] = "preserved.com:80" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("preserved.com:80", json.headers.host)
        end)

        it("forwards request Host:Port if port isn't default", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["Host"] = "preserved.com:123" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("preserved.com:123", json.headers.host)
        end)

        it("forwards request Host even if not matched by [hosts]", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["Host"] = "preserved.com" },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("preserved.com", json.headers.host)
        end)
      end)
    end)

    describe("edge-cases", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            paths      = { "/" },
          },
          {
            strip_path = true,
            paths      = { "/foobar" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("root / [uri] for a catch-all rule", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["kong-debug"] = 1 }
        })

        assert.response(res).has_status(200)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foobar/get",
          headers = { ["kong-debug"] = 1 }
        })

        assert.response(res).has_status(200)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)
    end)

    describe("[snis] for HTTPs connections", function()
      local routes
      local proxy_ssl_client

      lazy_setup(function()
        local configs = {
          {
            protocols = { "https" },
            snis = { "www.example.org" },
            service = {
              name = "service_behind_www.example.org"
            },
          },
          {
            protocols = { "https" },
            snis = { "example.org" },
            service = {
              name = "service_behind_example.org"
            },
          },
        }

        if flavor ~= "traditional" then
          local not_trad_configs = {
            {
              protocols = { "https" },
              snis = { "*.foo.test" },
              service = {
                name = "service_behind_wild.foo.test"
              },
            },
            {
              protocols = { "https" },
              snis = { "bar.*" },
              service = {
                name = "service_behind_bar.wild"
              },
            },
          }

          for _, v in ipairs(not_trad_configs) do
            table_insert(configs, v)
          end
        end

        routes = insert_routes(bp, configs)
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      after_each(function()
        if proxy_ssl_client then
          proxy_ssl_client:close()
        end
      end)

      it("matches a route based on its 'snis' attribute", function()
        proxy_ssl_client = helpers.proxy_ssl_client(nil, "www.example.org")

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("service_behind_www.example.org",
                     res.headers["kong-service-name"])

        res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/201",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(201, res)
        assert.equal("service_behind_www.example.org",
                     res.headers["kong-service-name"])

        proxy_ssl_client:close()

        proxy_ssl_client = helpers.proxy_ssl_client(nil, "example.org")

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("service_behind_example.org",
                     res.headers["kong-service-name"])

        res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/201",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(201, res)
        assert.equal("service_behind_example.org",
                     res.headers["kong-service-name"])
      end)

      if flavor ~= "traditional" then
        it("matches a route based on its leftmost wildcard sni", function()
          for _, sni in ipairs({"a.foo.test", "a.b.foo.test"}) do
            proxy_ssl_client = helpers.proxy_ssl_client(nil, sni)

            local res = assert(proxy_ssl_client:send {
              method  = "GET",
              path    = "/status/200",
              headers = { ["kong-debug"] = 1 },
            })
            assert.res_status(200, res)
            assert.equal("service_behind_wild.foo.test",
                         res.headers["kong-service-name"])

            proxy_ssl_client:close()
          end
        end)

        it("matches a route based on its rightmost wildcard sni", function()
          for _, sni in ipairs({"bar.x", "bar.y.z"}) do
            proxy_ssl_client = helpers.proxy_ssl_client(nil, sni)

            local res = assert(proxy_ssl_client:send {
              method  = "GET",
              path    = "/status/200",
              headers = { ["kong-debug"] = 1 },
            })
            assert.res_status(200, res)
            assert.equal("service_behind_bar.wild",
                         res.headers["kong-service-name"])

            proxy_ssl_client:close()
          end
        end)
      end -- if flavor ~= "traditional" then
    end)

    describe("tls_passthrough", function()
      local routes
      local proxy_ssl_client

      lazy_setup(function()
        local configs = {
          {
            protocols = { "tls_passthrough" },
            snis = { "www.example.org" },
            service = {
              name = "service_behind_www.example.org",
              host = helpers.mock_upstream_ssl_host,
              port = helpers.mock_upstream_ssl_port,
              protocol = "tcp",
            },
          },
          {
            protocols = { "tls_passthrough" },
            snis = { "example.org" },
            service = {
              name = "service_behind_example.org",
              host = helpers.mock_upstream_ssl_host,
              port = helpers.mock_upstream_ssl_port,
              protocol = "tcp",
            },
          },
        }

        if flavor ~= "traditional" then
          local not_trad_configs = {
            {
              protocols = { "tls_passthrough" },
              snis = { "*.foo.test" },
              service = {
                name = "service_behind_wild.foo.test",
                host = helpers.mock_upstream_ssl_host,
                port = helpers.mock_upstream_ssl_port,
                protocol = "tcp",
              },
            },
            {
              protocols = { "tls_passthrough" },
              snis = { "bar.*" },
              service = {
                name = "service_behind_bar.wild",
                host = helpers.mock_upstream_ssl_host,
                port = helpers.mock_upstream_ssl_port,
                protocol = "tcp",
              },
            },
          }

          for _, v in ipairs(not_trad_configs) do
            table_insert(configs, v)
          end
        end

        routes = insert_routes(bp, configs)
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      after_each(function()
        if proxy_ssl_client then
          proxy_ssl_client:close()
        end
      end)

      it("matches a route based on its 'snis' attribute", function()
        -- config propagates to stream subsystems not instantly
        -- try up to 10 seconds with step of 2 seconds
        -- in vagrant it takes around 6 seconds
        helpers.wait_until(function()
          proxy_ssl_client = helpers.http_client("127.0.0.1", stream_tls_listen_port)
          local ok = proxy_ssl_client:ssl_handshake(nil, "www.example.org", false) -- explicit no-verify
          if not ok then
            proxy_ssl_client:close()
            return false
          end
          return true
        end, 10, 2)

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/201",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(201, res)

        proxy_ssl_client:close()

        proxy_ssl_client = helpers.http_client("127.0.0.1", stream_tls_listen_port)
        assert(proxy_ssl_client:ssl_handshake(nil, "example.org", false)) -- explicit no-verify

        local res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        res = assert(proxy_ssl_client:send {
          method  = "GET",
          path    = "/status/201",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(201, res)

        proxy_ssl_client:close()
      end)

      if flavor ~= "traditional" then
        it("matches a route based on its leftmost wildcard sni", function()
          for _, sni in ipairs({"a.foo.test", "a.b.foo.test"}) do
            -- config propagates to stream subsystems not instantly
            -- try up to 10 seconds with step of 2 seconds
            -- in vagrant it takes around 6 seconds
            helpers.wait_until(function()
              proxy_ssl_client = helpers.http_client("127.0.0.1", stream_tls_listen_port)
              local ok = proxy_ssl_client:ssl_handshake(nil, sni, false) -- explicit no-verify
              if not ok then
                proxy_ssl_client:close()
                return false
              end
              return true
            end, 10, 2)

            local res = assert(proxy_ssl_client:send {
              method  = "GET",
              path    = "/status/200",
              headers = { ["kong-debug"] = 1 },
            })
            assert.res_status(200, res)

            proxy_ssl_client:close()
          end
        end)

        it("matches a route based on its rightmost wildcard sni", function()
          for _, sni in ipairs({"bar.x", "bar.y.z"}) do
            -- config propagates to stream subsystems not instantly
            -- try up to 10 seconds with step of 2 seconds
            -- in vagrant it takes around 6 seconds
            helpers.wait_until(function()
              proxy_ssl_client = helpers.http_client("127.0.0.1", stream_tls_listen_port)
              local ok = proxy_ssl_client:ssl_handshake(nil, sni, false) -- explicit no-verify
              if not ok then
                proxy_ssl_client:close()
                return false
              end
              return true
            end, 10, 2)

            local res = assert(proxy_ssl_client:send {
              method  = "GET",
              path    = "/status/200",
              headers = { ["kong-debug"] = 1 },
            })
            assert.res_status(200, res)

            proxy_ssl_client:close()
          end
        end)
      end -- if flavor ~= "traditional" then
    end)

    describe("[#headers]", function()
      local routes

      after_each(function()
        remove_routes(strategy, routes)
      end)

      it("matches by header", function()
        routes = insert_routes(bp, {
          {
            headers = { version = { "v1", "v2" } },
          },
          {
            headers = { version = { "v3" } },
          },
        })

        local res
        helpers.wait_until(function()
          res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = {
              ["Host"]       = "domain.test",
              ["version"]    = "v1",
              ["kong-debug"] = 1,
            }
          })
          return pcall(function()
            assert.res_status(200, res)
          end)
        end, 10)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Host"]       = "domain.test",
            ["version"]    = "v3",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)

      it("matches headers in a case-insensitive way", function()
        routes = insert_routes(bp, {
          {
            headers = { Version = { "v1", "v2" } },
          },
          {
            headers = { version = { "V3" } },
          },
        })

        local res
        helpers.wait_until(function()
          res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = {
              ["Host"]       = "domain.test",
              ["version"]    = "v1",
              ["kong-debug"] = 1,
            }
          })

          return pcall(function()
            assert.res_status(200, res)
            assert.equal(routes[1].id, res.headers["kong-route-id"])
          end)
        end, 10)

        assert.res_status(200, res)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Host"]       = "domain.test",
            ["Version"]    = "v3",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)

      it("prioritizes Routes with more headers", function()
        routes = insert_routes(bp, {
          {
            headers = {
              version = { "v1", "v2" },
            },
          },
          {
            headers = {
              version = { "v3" },
              location = { "us-east" },
            },
          },
          {
            headers = {
              version = { "v3" },
            },
          },
        })

        local res
        helpers.wait_until(function()
          res = assert(proxy_client:send {
            method  = "GET",
            path    = "/",
            headers = {
              ["Host"]       = "domain.test",
              ["version"]    = "v3",
              ["location"]   = "us-east",
              ["kong-debug"] = 1,
            }
          })
          return res.headers["kong-route-id"] == routes[2].id
        end, 5)

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Host"]       = "domain.test",
            ["version"]    = "v3",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[3].id,           res.headers["kong-route-id"])
        assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[3].service.name, res.headers["kong-service-name"])
      end)

      it("caching do not ignore headers (regression)", function()
        routes = insert_routes(bp, {
          {
            service    = {
              name     = "first",
            },
            hosts      = { "example.test" },
            paths      = { "/test" },
            headers    = { headertest = { "itsatest" } },
          },
          {
            service    = {
              name     = "second",
            },
            hosts      = { "example.test" },
            paths      = { "/test" },
          },
        })

        local res
        helpers.wait_until(function()
          res = assert(proxy_client:send {
            method  = "GET",
            path    = routes[1].paths[1],
            headers = {
              ["Host"]       = routes[1].hosts[1],
              ["headertest"] = "itsatest",
              ["kong-debug"] = 1,
            }
          })
          return pcall(function()
            assert.res_status(200, res)
          end)
        end, 10)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = routes[2].paths[1],
          headers = {
            ["Host"]       = routes[2].hosts[1],
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)
        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = routes[1].paths[1],
          headers = {
            ["Host"]       = routes[1].hosts[1],
            ["headertest"] = "itsatest",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)
        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])

      end)
    end)

    describe("[paths] + [#headers]", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            headers = {
              version = { "v1", "v2" },
            },
            paths = { "/root" },
          },
          {
            strip_path = true,
            headers = {
              version = { "v1", "v2" },
            },
            paths = { "/root/fixture" },
          },
          {
            strip_path = true,
            headers = {
              version = { "v1", "v2" },
              location = { "us-east" },
            },
            paths = { "/root" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("prioritizes Routes with more headers", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["version"]    = "v2",
            ["location"]   = "us-east",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(404, res)

        assert.equal(routes[3].id,           res.headers["kong-route-id"])
        assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[3].service.name, res.headers["kong-service-name"])
      end)

      it("prioritizes longer paths if same number of headers", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["version"]    = "v2",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)
    end)

    if not enable_buffering then
    describe("[snis] for #grpcs connections", function()
      local routes
      local grpcs_proxy_ssl_client

      lazy_setup(function()
        local configs = {
          {
            protocols = { "grpcs" },
            snis = { "grpcs_1.test" },
            service = {
              name = "grpcs_1",
              url = helpers.grpcbin_ssl_url,
            },
          },
          {
            protocols = { "grpcs" },
            snis = { "grpcs_2.test" },
            service = {
              name = "grpcs_2",
              url = helpers.grpcbin_ssl_url,
            },
          },
        }

        if flavor ~= "traditional" then
          local not_trad_configs = {
            {
              protocols = { "grpcs" },
              snis = { "*.grpcs_3.test" },
              service = {
                name = "grpcs_3",
                url = helpers.grpcbin_ssl_url,
              },
            },
            {
              protocols = { "grpcs" },
              snis = { "grpcs_4.*" },
              service = {
                name = "grpcs_4",
                url = helpers.grpcbin_ssl_url,
              },
            },
          }

          for _, v in ipairs(not_trad_configs) do
            table_insert(configs, v)
          end
        end

        routes = insert_routes(bp, configs)
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("matches a route based on its 'snis' attribute", function()
        grpcs_proxy_ssl_client = helpers.proxy_client_grpcs("grpcs_1.test")

        local ok, resp = assert(grpcs_proxy_ssl_client({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-H"] = "'kong-debug: 1'",
            ["-v"] = true, -- verbose so we get response headers
          }
        }))
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-service-name: grpcs_1", resp, nil, true)

        grpcs_proxy_ssl_client = helpers.proxy_client_grpcs("grpcs_2.test")
        local ok, resp = assert(grpcs_proxy_ssl_client({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-H"] = "'kong-debug: 1'",
            ["-v"] = true, -- verbose so we get response headers
          }
        }))
        assert.truthy(ok)
        assert.truthy(resp)
        assert.matches("kong-service-name: grpcs_2", resp, nil, true)
      end)

      if flavor ~= "traditional" then
        it("matches a route based on its leftmost wildcard sni", function()
          for _, sni in ipairs({"a.grpcs_3.test", "a.b.grpcs_3.test"}) do
            grpcs_proxy_ssl_client = helpers.proxy_client_grpcs(sni)

            local ok, resp = assert(grpcs_proxy_ssl_client({
              service = "hello.HelloService.SayHello",
              body = {
                greeting = "world!"
              },
              opts = {
                ["-H"] = "'kong-debug: 1'",
                ["-v"] = true, -- verbose so we get response headers
              }
            }))
            assert.truthy(ok)
            assert.truthy(resp)
            assert.matches("kong-service-name: grpcs_3", resp, nil, true)
          end
        end)

        it("matches a route based on its rightmost wildcard sni", function()
          for _, sni in ipairs({"grpcs_4.x", "grpcs_4.y.z"}) do
            grpcs_proxy_ssl_client = helpers.proxy_client_grpcs(sni)

            local ok, resp = assert(grpcs_proxy_ssl_client({
              service = "hello.HelloService.SayHello",
              body = {
                greeting = "world!"
              },
              opts = {
                ["-H"] = "'kong-debug: 1'",
                ["-v"] = true, -- verbose so we get response headers
              }
            }))
            assert.truthy(ok)
            assert.truthy(resp)
            assert.matches("kong-service-name: grpcs_4", resp, nil, true)
          end
        end)
      end -- if flavor ~= "traditional" then
    end)
    end -- not enable_buffering

    describe("[paths] + [methods]", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          [1] = {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/unrelated/longer/uri/that/should/not/match", "/root/fixture" },
            hosts      = { "ahost.test" },
            service    = { path = "/status/201" },
          },
          [2] = {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/root/fixture/get" },
            hosts      = { "ahost.test" },
            service    = { path = "/status/202" },
          },
          [3] = {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/root/fixture/get" },
            hosts      = { "anotherhost.test" },
            service    = { path = "/status/203" },
          },
          [4] = {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/root/fixture/get" },
            hosts      = { "onemorehost.test" },
            service    = { path = "/status/204" },
          },

          [5] = {
            strip_path = true,
            name       = "public-apiv1",
            paths      = { "/rest/devportal/api/v1", "/rest/devportal" },
            hosts      = { "api.local" },
            service    = { path = "/status/205" },
          },
          [6] = {
            strip_path = true,
            name       = "aux",
            paths      = { "/rest/devportal/aux" },
            hosts      = { "api.local" },
            service    = { path = "/status/206" },
          },
          [7] = {
            strip_path = true,
            name       = "aux-host",
            paths      = { "/rest/devportal/aux" },
            hosts      = { "test-api.local" },
            service    = { path = "/status/207" },
          },
          [8] = {
            strip_path = true,
            name       = "aux-host2",
            paths      = { "/rest/devportal/aux" },
            hosts      = { "atest-api.local" },
            service    = { path = "/status/208" },
          },
          [9] = {
            strip_path = true,
            name       = "devportal-route-2",
            paths      = { "/rest/devportal" },
            hosts      = { "atest-api.local" },
            service    = { path = "/status/209" },
          },

          [10] = {
            strip_path = true,
            name       = "concat_test-public-apiv1",
            paths      = { "/concat_test/devportal/api/v1", "/concat_test/devportal" },
            hosts      = { "api.local" },
          },
          [11] = {
            strip_path = true,
            name       = "concat_test-aux",
            paths      = { "/concat_test/devportal/aux" },
            hosts      = { "api.local" },
          },
          [12] = {
            strip_path = true,
            name       = "concat_test-aux-host",
            paths      = { "/concat_test/devportal/aux" },
            hosts      = { "test-api.local" },
          },
          [13] = {
            strip_path = true,
            name       = "concat_test-aux-host2",
            paths      = { "/concat_test/devportal/aux" },
            hosts      = { "atest-api.local" },
          },
          [14] = {
            strip_path = true,
            name       = "concat_test-devportal-route-2",
            paths      = { "/concat_test/devportal" },
            hosts      = { "atest-api.local" },
          },

        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it_trad_only("regression test for #5438", function()
        for i = 1, 9 do
          for j = 1, #routes[i].paths do
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = routes[i].paths[j],
              headers = {
                ["kong-debug"] = 1,
                ["host"] = routes[i].hosts[1],
              }
            })

            assert.res_status(200 + i, res)

            assert.equal(routes[i].id,           res.headers["kong-route-id"])
            assert.equal(routes[i].service.id,   res.headers["kong-service-id"])
            assert.equal(routes[i].service.name, res.headers["kong-service-name"])

          end
        end
      end)

      it_trad_only("regression test for #5438 concatenating paths", function()
        for i = 10, 14 do
          for j = 1, #routes[i].paths do
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = routes[i].paths[j] .. "/status/418",
              headers = {
                ["kong-debug"] = 1,
                ["host"] = routes[i].hosts[1],
              }
            })

            assert.res_status(418, res)

            assert.equal(routes[i].id,           res.headers["kong-route-id"])
            assert.equal(routes[i].service.id,   res.headers["kong-service-id"])
            assert.equal(routes[i].service.name, res.headers["kong-service-name"])

          end
        end
      end)

      it_trad_only("regression test for #5438 part 2", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/rest/devportal",
          headers = {
            ["kong-debug"] = 1,
            ["host"] = "atest-api.local",
          }
        })

        assert.res_status(209, res)

        assert.equal(routes[9].id,           res.headers["kong-route-id"])
        assert.equal(routes[9].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[9].service.name, res.headers["kong-service-name"])
      end)

      it_trad_only("prioritizes longer URIs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["kong-debug"] = 1,
            ["host"] = "ahost.test",
          }
        })

        assert.res_status(202, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)

      it("prioritizes host over longer URIs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["kong-debug"] = 1,
            ["host"] = "anotherhost.test",
          }
        })

        assert.res_status(203, res)

        assert.equal(routes[3].id,           res.headers["kong-route-id"])
        assert.equal(routes[3].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[3].service.name, res.headers["kong-service-name"])
      end)

      it("do not match incomplete URIs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["kong-debug"] = 1,
            ["host"] = "ahost.test",
          }
        })

        assert.res_status(404, res)
      end)
    end)

    describe("[paths] + [hosts]", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            hosts      = { "route.com" },
            paths      = { "/root/fixture", "/root/fixture/non-matching-but-longer" },
          },
          {
            strip_path = true,
            hosts      = { "route.com" },
            paths      = { "/root/fixture/get" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it_trad_only("prioritizes longer URIs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["Host"]       = "route.com",
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)
    end)

    describe("slash handling", function()
      describe("(plain)", function()
        local routes

        lazy_setup(function()
          routes = {}

          for i, line in ipairs(path_handling_tests) do
            for j, test in ipairs(line:expand()) do
              if flavor == "traditional" or test.path_handling == "v0" then
                routes[#routes + 1] = {
                  strip_path   = test.strip_path,
                  path_handling = test.path_handling,
                  paths        = test.route_path and { test.route_path } or nil,
                  hosts        = { "localbin-" .. i .. "-" .. j .. ".com" },
                  service = {
                    name = "plain_" .. i .. "-" .. j,
                    path = test.service_path,
                  }
                }
              end
            end
          end

          routes = insert_routes(bp, routes)
        end)

        lazy_teardown(function()
          for _, r in ipairs(routes) do
            remove_routes(strategy, r)
          end
        end)

        for i, line in ipairs(path_handling_tests) do
          for j, test in ipairs(line:expand()) do
            if flavor == "traditional" or test.path_handling == "v0" then
              local strip = test.strip_path and "on" or "off"
              local route_uri_or_host
              if test.route_path then
                route_uri_or_host = "uri " .. test.route_path
              else
                route_uri_or_host = "host localbin-" .. i .. "-" .. j .. ".com"
              end

              local description = string.format("(%d-%d) %s with %s, strip = %s, %s when requesting %s",
                i, j, test.service_path, route_uri_or_host, strip, test.path_handling, test.request_path)

              it(description, function()
                helpers.wait_until(function()
                  local res = assert(proxy_client:get(test.request_path, {
                    headers = {
                      ["Host"] = "localbin-" .. i .. "-" .. j .. ".com",
                    }
                  }))

                  return pcall(function()
                    local data = assert.response(res).has.jsonbody()
                    assert.equal(test.expected_path, data.vars.request_uri)
                  end)
                end, 10)
              end)
            end
          end
        end
      end)

      describe("(regex)", function()
        local function make_a_regex(path)
          return "~/[0]?" .. path:sub(2, -1)
        end

        local routes

        lazy_setup(function()
          routes = {}

          for i, line in ipairs(path_handling_tests) do
            if line.route_path then  -- skip if hostbased match
              for j, test in ipairs(line:expand()) do
                if flavor == "traditional" or test.path_handling == "v0" then
                  routes[#routes + 1] = {
                    strip_path   = test.strip_path,
                    paths        = test.route_path and { make_a_regex(test.route_path) } or nil,
                    path_handling = test.path_handling,
                    hosts        = { "localbin-" .. i .. "-" .. j .. ".com" },
                    service = {
                      name = "make_regex_" .. i .. "-" .. j,
                      path = test.service_path,
                    }
                  }
                end
              end
            end
          end

          routes = insert_routes(bp, routes)
        end)

        lazy_teardown(function()
          remove_routes(strategy, routes)
        end)

        for i, line in ipairs(path_handling_tests) do
          if line.route_path then  -- skip if hostbased match
            for j, test in ipairs(line:expand()) do
              if flavor == "traditional" or test.path_handling == "v0" then
                local strip = test.strip_path and "on" or "off"

                local description = string.format("(%d-%d) %s with uri %s, strip = %s, %s when requesting %s",
                  i, j, test.service_path, make_a_regex(test.route_path), strip, test.path_handling, test.request_path)

                it(description, function()
                  local res = assert(proxy_client:get(test.request_path, {
                    headers = { Host = "localbin-" .. i .. "-" .. j .. ".com" },
                  }))

                  local data = assert.response(res).has.jsonbody()
                  assert.truthy(data.vars)
                  assert.equal(test.expected_path, data.vars.request_uri)
                end)
              end
            end
          end
        end
      end)

      describe("router rebuilds", function()
        local routes

        lazy_teardown(function()
          remove_routes(routes)
        end)

        it("when Routes have 'regex_priority = nil'", function()
          -- Regression test for issue:
          -- https://github.com/Kong/kong/issues/4254
          routes = insert_routes(bp, {
            {
              methods = { "GET" },
              regex_priority = 1,
            },
            {
              methods = { "POST", "PUT" },
              regex_priority = ngx.null,
            },
          })

          local res = assert(proxy_client:send {
            method  = "GET",
          })

          assert.response(res).has_status(200)
        end)
      end)
    end)
  end)

  for _, consistency in ipairs({ "strict", "eventual" }) do
    describe("Router [#" .. strategy .. ", flavor = " .. flavor ..
      ", consistency = " .. consistency .. "] at startup" , function()
      local proxy_client
      local route

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, {
          "enable-buffering",
        })

        route = bp.routes:insert({
          methods    = { "GET" },
          protocols  = { "http" },
          strip_path = false,
        })

        if enable_buffering then
          bp.plugins:insert {
            name = "enable-buffering",
            protocols = { "http", "https", "grpc", "grpcs" },
          }
        end

        assert(helpers.start_kong({
          router_flavor = flavor,
          worker_consistency = consistency,
          database = strategy,
          nginx_worker_processes = 4,
          plugins = "bundled,enable-buffering",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          allow_debug_header = true,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
      end)

      it("uses configuration from datastore or declarative_config", function()
        for _ = 1, 1000 do
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = { ["kong-debug"] = 1 },
          })

          assert.response(res).has_status(200)

          assert.equal(route.service.name, res.headers["kong-service-name"])
          proxy_client:close()
        end
      end)

      it("#db worker respawn correctly rebuilds router", function()
        local admin_client = helpers.admin_client()

        local res = assert(admin_client:post("/routes", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            paths = { "/foo" },
          },
        }))
        assert.res_status(201, res)
        admin_client:close()

        local workers_before = helpers.get_kong_workers()
        assert(helpers.signal_workers(nil, "-TERM"))
        helpers.wait_until_no_common_workers(workers_before, 1) -- respawned

        proxy_client:close()
        proxy_client = helpers.proxy_client()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.response(res).has_status(503)
        local json = cjson.decode(body)
        assert.equal("no Service found with those values", json.message)
      end)

      it("#db rebuilds router correctly after passing route with special escape", function()
        local admin_client = helpers.admin_client()

        local res = assert(admin_client:post("/routes", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            -- this is a valid regex path in Rust.regex 1.8
            paths = { "~/delay/(?<delay>[^\\/]+)$", },
          },
        }))
        assert.res_status(201, res)

        helpers.wait_for_all_config_update()

        local res = assert(admin_client:post("/routes", {
          headers = { ["Content-Type"] = "application/json" },
          body = {
            paths = { "/foo" },
          },
        }))
        assert.res_status(201, res)

        admin_client:close()

        helpers.wait_for_all_config_update()

        proxy_client:close()
        proxy_client = helpers.proxy_client()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo",
          headers = { ["kong-debug"] = 1 },
        })

        local body = assert.response(res).has_status(503)
        local json = cjson.decode(body)
        assert.equal("no Service found with those values", json.message)
      end)
    end)
  end

  describe("disable allow_debug_header config" , function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "enable-buffering",
      })

      bp.routes:insert({
        methods    = { "GET" },
        protocols  = { "http" },
        strip_path = false,
      })

      if enable_buffering then
        bp.plugins:insert {
          name = "enable-buffering",
          protocols = { "http", "https", "grpc", "grpcs" },
        }
      end

      assert(helpers.start_kong({
        router_flavor = flavor,
        database = strategy,
        nginx_worker_processes = 4,
        plugins = "bundled,enable-buffering",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("disable allow_debug_header config", function()
      for _ = 1, 1000 do
        proxy_client = helpers.proxy_client()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = { ["kong-debug"] = 1 },
        })

        assert.response(res).has_status(200)

        assert.is_nil(res.headers["kong-service-name"])
        assert.is_nil(res.headers["kong-route-name"])
        proxy_client:close()
      end
    end)
  end)
end
end
end


-- http expression 'http.queries.*'
do
  local function reload_router(flavor)
    helpers = require("spec.internal.module").reload_helpers(flavor)
  end


  local flavor = "expressions"

  for _, strategy in helpers.each_strategy() do
    describe("Router [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
      local proxy_client

      reload_router(flavor)

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local service = bp.services:insert {
          name = "global-cert",
        }

        bp.routes:insert {
          protocols = { "http" },
          expression = [[http.path == "/foo/bar" && http.queries.a == "1"]],
          priority = 100,
          service   = service,
        }

        bp.routes:insert {
          protocols = { "http" },
          expression = [[http.path == "/foo" && http.queries.a == ""]],
          priority = 100,
          service   = service,
        }

        bp.routes:insert {
          protocols = { "http" },
          expression = [[http.path == "/foobar" && any(http.queries.a) == "2"]],
          priority = 100,
          service   = service,
        }

        assert(helpers.start_kong({
          router_flavor = flavor,
          database    = strategy,
          nginx_conf  = "spec/fixtures/custom_nginx.template",
        }))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
      end)

      it("query has wrong value", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/bar",
          query   = "a=x",
        })
        assert.res_status(404, res)
      end)

      it("query has one value", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/bar",
          query   = "a=1",
        })
        assert.res_status(200, res)
      end)

      it("query value is empty string", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo",
          query   = "a=",
        })
        assert.res_status(200, res)
      end)

      it("query has no value", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo",
          query   = "a&b=999",
        })
        assert.res_status(200, res)
      end)

      it("query has multiple values", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foobar",
          query   = "a=2&a=10",
        })
        assert.res_status(200, res)
      end)

      it("query does not match multiple values", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foobar",
          query   = "a=10&a=20",
        })
        assert.res_status(404, res)
      end)

    end)

    describe("Router [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
      local proxy_client

      reload_router(flavor)

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        })

        local service = bp.services:insert {
          name = "global-cert",
        }

        bp.routes:insert {
          protocols = { "http" },
          expression = [[http.path == "/foo/bar"]],
          priority = 2^46 - 1,
          service = service,
        }

        assert(helpers.start_kong({
          router_flavor = flavor,
          database    = strategy,
          nginx_conf  = "spec/fixtures/custom_nginx.template",
          allow_debug_header = true,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
      end)

      it("can set route.priority to 2^46 - 1", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/bar",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        local route_id = res.headers["kong-route-id"]

        local admin_client = helpers.admin_client()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/routes/" .. route_id,
        })
        local body = assert.response(res).has_status(200)
        assert(string.find(body, [["priority":70368744177663]]))

        local json = cjson.decode(body)
        assert.equal(2^46 - 1, json.priority)

        admin_client:close()
      end)

    end)

  end   -- strategy

end -- http expression 'http.queries.*'
