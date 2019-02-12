local admin_api = require "spec.fixtures.admin_api"
local helpers = require "spec.helpers"
local cjson   = require "cjson"


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

  for i = 1, #routes do
    local route = routes[i]
    local service = route.service or {}

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
    route.service = service

    if not route.protocol then
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
      path    = "/configure",
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

  return routes
end

local function remove_routes(strategy, routes)
  if strategy == "off" or not routes then
    return
  end

  local services = {}

  for _, route in ipairs(routes) do
    local sid = route.service.id
    if not services[sid] then
      services[sid] = route.service
      table.insert(services, services[sid])
    end
  end

  for _, route in ipairs(routes) do
    admin_api.routes:remove({ id = route.id })
  end

  for _, service in ipairs(services) do
    admin_api.services:remove(service)
  end
end

for _, strategy in helpers.each_strategy() do
  describe("Router [#" .. strategy .. "]" , function()
    local proxy_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "apis",
      })

      assert(helpers.start_kong({
        database = strategy,
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
            paths      = { [[/users/\d+/profile]] },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/anything",
            },
          },
        })
        first_service_name = routes[1].service.name
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
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
    end)

    describe("URI regexes order of evaluation with created_at", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            created_at = 1234567890,
            strip_path = true,
            paths      = { "/status/(re)" },
            service    = {
              name     = "regex_1",
              path     = "/status/200",
            },
          },
          {
            created_at = 1234567891,
            strip_path = true,
            paths      = { "/status/(r)" },
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

      it("depends on created_at field", function()
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
            paths      = { "/status/(?<foo>re)" },
            service    = {
              name     = "regex_1",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
          {
            strip_path = true,
            paths      = { "/status/(re)" },
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
            paths      = { "/status/(ab)" },
            service    = {
              name     = "regex_3",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
          {
            created_at = 1234567891,
            strip_path = true,
            paths      = { "/status/(ab)c?" },
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

      it("depends on created_at if regex_priority is tie", function()
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

    describe("percent-encoded URIs", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            paths      = { "/endel%C3%B8st" },
          },
          {
            strip_path = true,
            paths      = { "/foo/../bar" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("routes when [paths] is percent-encoded", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/endel%C3%B8st",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(200, res)

        assert.equal(routes[1].id,           res.headers["kong-route-id"])
        assert.equal(routes[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[1].service.name, res.headers["kong-service-name"])
      end)

      it("matches against non-normalized URI", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/foo/../bar",
          headers = { ["kong-debug"] = 1 },
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
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
            hosts         = { "preserved.com" },
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

      describe(" = true", function()
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

        it("forwards request Host:Port even if port is default", function()
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

    describe("[paths] + [methods]", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/root" },
          },
          {
            strip_path = true,
            methods    = { "GET" },
            paths      = { "/root/fixture" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("prioritizes longer URIs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/root/fixture/get",
          headers = {
            ["kong-debug"] = 1,
          }
        })

        assert.res_status(200, res)

        assert.equal(routes[2].id,           res.headers["kong-route-id"])
        assert.equal(routes[2].service.id,   res.headers["kong-service-id"])
        assert.equal(routes[2].service.name, res.headers["kong-service-name"])
      end)
    end)

    describe("[paths] + [hosts]", function()
      local routes

      lazy_setup(function()
        routes = insert_routes(bp, {
          {
            strip_path = true,
            hosts      = { "route.com" },
            paths      = { "/root" },
          },
          {
            strip_path = true,
            hosts      = { "route.com" },
            paths      = { "/root/fixture" },
          },
        })
      end)

      lazy_teardown(function()
        remove_routes(strategy, routes)
      end)

      it("prioritizes longer URIs", function()
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

    describe("slash handing", function()
      local checks = {
        -- upstream url    paths           request path    expected path           strip uri
        {  "/",            "/",            "/",            "/",                    true      }, -- 1
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             true      },
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            true      },
        {  "/",            "/foo/bar",     "/foo/bar",     "/",                    true      },
        {  "/",            "/foo/bar",     "/foo/bar/",    "/",                    true      },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    true      },
        {  "/fee/bor",     "/",            "/",            "/fee/bor",             true      },
        {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      true      },
        {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/bor",             true      }, -- 10
        {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/bor",             true      },
        {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            true      },
        {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     true      },
        {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/",            true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/",            true      },
        {  "/",            "/",            "/",            "/",                    false     },
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             false     }, -- 20
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            false     },
        {  "/",            "/foo/bar",     "/foo/bar",     "/foo/bar",             false     },
        {  "/",            "/foo/bar",     "/foo/bar/",    "/foo/bar/",            false     },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            false     },
        {  "/fee/bor",     "/",            "/",            "/fee/bor",             false     },
        {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/borfoo/bar/",     false     }, -- 30
        {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            false     },
        {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        -- the following block runs the same tests, but with a request path that is longer
        -- than the matched part, so either matches in the middle of a segment, or has an
        -- additional segment.
        {  "/",            "/",            "/foo/bars",    "/foo/bars",            true      },
        {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           true      },
        {  "/",            "/foo/bar",     "/foo/bars",    "/s",                   true      },
        {  "/",            "/foo/bar/",    "/foo/bar/s",   "/s",                   true      }, -- 40
        {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     true      },
        {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    true      },
        {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/bors",            true      },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/bors",            true      },
        {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    true      },
        {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/s",           true      },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/s",           true      },
        {  "/",            "/",            "/foo/bars",    "/foo/bars",            false     },
        {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           false     }, -- 50
        {  "/",            "/foo/bar",     "/foo/bars",    "/foo/bars",            false     },
        {  "/",            "/foo/bar/",    "/foo/bar/s",   "/foo/bar/s",           false     },
        {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     false     },
        {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/borfoo/bars",     false     },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
        {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    false     },
        {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/foo/bars",    false     },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     }, -- 60
        -- the following block matches on host, instead of path
        {  "/",            nil,            "/",            "/",                    false     },
        {  "/",            nil,            "/foo/bar",     "/foo/bar",             false     },
        {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            false     },
        {  "/fee/bor",     nil,            "/",            "/fee/bor",             false     },
        {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            false     },
        {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/",            nil,            "/",            "/",                    true      }, -- 70
        {  "/",            nil,            "/foo/bar",     "/foo/bar",             true      },
        {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            true      },
        {  "/fee/bor",     nil,            "/",            "/fee/bor",             true      },
        {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      true      },
        {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
        {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            true      },
        {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     true      },
        {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
      }

      describe("(plain)", function()
        local routes

        lazy_setup(function()
          routes = {}

          for i, args in ipairs(checks) do
            routes[i] = {
              strip_path   = args[5],
              paths        = args[2] and {
                args[2],
              } or nil,
              hosts        = {
                "localbin-" .. i .. ".com",
              },
              service = {
                name = "plain_" .. i,
                path = args[1]
              }
            }
          end

          routes = insert_routes(bp, routes)
        end)

        lazy_teardown(function()
          for _, r in ipairs(routes) do
            remove_routes(strategy, r)
          end
        end)

        local function check(i, request_uri, expected_uri)
          return function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = request_uri,
              headers = {
                ["Host"] = "localbin-" .. i .. ".com",
              }
            })

            local json = assert.res_status(200, res)
            local data = cjson.decode(json)

            assert.equal(expected_uri, data.vars.request_uri)
          end
        end

        for i, args in ipairs(checks) do
          local config = "(strip = " .. (args[5] and "on" or "off") .. ")"

          it("(" .. i .. ") " .. config ..
             " is not appended to upstream url " .. args[1] ..
             " (with " .. (args[2] and ("uri " .. args[2]) or
             ("host test" .. i .. ".domain.org")) .. ")" ..
             " when requesting " .. args[3], function()
            check(i, args[3], args[4])
          end)
        end
      end)

      describe("(regex)", function()
        local function make_a_regex(path)
          return "/[0]?" .. path:sub(2, -1)
        end

        local routes

        lazy_setup(function()
          routes = {}

          for i, args in ipairs(checks) do
            routes[i] = {
              strip_path   = args[5],
              paths        = args[2] and {
                make_a_regex(args[2]),
              } or nil,
              hosts        = {
                "localbin-" .. i .. ".com",
              },
              service = {
                name = "make_regex_" .. i,
                path = args[1]
              }
            }
          end

          routes = insert_routes(bp, routes)
        end)

        lazy_teardown(function()
          remove_routes(strategy, routes)
        end)

        local function check(i, request_uri, expected_uri)
          return function()
            local res = assert(proxy_client:send {
              method  = "GET",
              path    = request_uri,
              headers = {
                ["Host"] = "localbin-" .. i .. ".com",
              }
            })

            local json = assert.res_status(200, res)
            local data = cjson.decode(json)

            assert.equal(expected_uri, data.vars.request_uri)
          end
        end

        for i, args in ipairs(checks) do
          if args[2] then  -- skip if hostbased match
            local config = "(strip = " .. (args[5] and "on" or "off") .. ")"

            it("(" .. i .. ") " .. config ..
              " is not appended to upstream url " .. args[1] ..
              " (with " .. (args[2] and ("uri " .. make_a_regex(args[2])) or
              ("host test" .. i .. ".domain.org")) .. ")" ..
              " when requesting " .. args[3], function()
              check(i, args[3], args[4])
            end)
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
end
