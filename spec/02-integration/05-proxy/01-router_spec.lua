local helpers = require "spec.helpers"
local cjson   = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Router [#" .. strategy .. "]" , function()
    local proxy_client
    local bp
    local db
    local dao

    local function insert_routes(routes)
      if type(routes) ~= "table" then
        return error("expected arg #1 to be a table", 2)
      end

      for i = 1, #routes do
        local route = routes[i]
        local service = route.service or {}

        if not service.name then
          service.name = "service-" .. i
        end

        if not service.host then
          service.host = helpers.mock_upstream_host
        end

        if not service.port then
          service.port = helpers.mock_upstream_port
        end

        if not service.protocol then
          service.protocol = helpers.mock_upstream_protocol
        end

        service = bp.services:insert(service)
        route.service = service

        if not route.protocol then
          route.protocols = { "http" }
        end

        route = bp.routes:insert(route)
        route.service = service


        routes[i] = route
      end

      return routes
    end

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
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
      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        assert(helpers.start_kong({
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
      end)

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
        assert.equal("no route and no API found with those values", json.message)
      end)
    end)

    describe("use-cases", function()
      local routes

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes = insert_routes {
          { -- service-1
            methods    = { "GET" },
            protocols  = { "http" },
            strip_path = false,
          },
          { -- service-2
            methods    = { "POST", "PUT" },
            paths      = { "/post", "/put" },
            protocols  = { "http" },
            strip_path = false,
          },
          { -- service-3
            paths      = { "/mock_upstream" },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/status",
            },
          },
          { -- service-4
            paths      = { "/private" },
            protocols  = { "http" },
            strip_path = false,
            service    = {
              path     = "/basic-auth",
            },
          },
          { -- service-5
            paths      = { [[/users/\d+/profile]] },
            protocols  = { "http" },
            strip_path = true,
            service    = {
              path     = "/anything",
            },
          },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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
          assert.matches("kong-service-name: service-1",
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
      local routes1, routes2

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes1 = insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(re)" },
            service    = {
              name     = "service-1",
              path     = "/status/200",
            },
          },
        }

        ngx.sleep(1)

        routes2 = insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(r)" },
            service    = {
              name     = "service-2",
              path     = "/status/200",
            },
          }
        }

        ngx.sleep(1)

        insert_routes {
          {
            strip_path = true,
            paths      = { "/status" },
            service    = {
              name     = "service-3",
              path     = "/status/200",
            },
          }
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      it("depends on created_at field", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/r",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        assert.equal(routes2[1].id,           res.headers["kong-route-id"])
        assert.equal(routes2[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes2[1].service.name, res.headers["kong-service-name"])

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/re",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)

        assert.equal(routes1[1].id,           res.headers["kong-route-id"])
        assert.equal(routes1[1].service.id,   res.headers["kong-service-id"])
        assert.equal(routes1[1].service.name, res.headers["kong-service-name"])
      end)
    end)

    describe("URI regexes order of evaluation with regex_priority", function()
      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        -- TEST 1 (regex_priority)

        insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(?<foo>re)" },
            service    = {
              name     = "service-1",
              path     = "/status/200",
            },
            regex_priority = 0,
          }
        }

        insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(re)" },
            service    = {
              name     = "service-2",
              path     = "/status/200",
            },
            regex_priority = 4, -- shadows service-4 (which is created before and is shorter)
          },
        }

        -- TEST 2 (tie breaker by created_at)

        insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(ab)" },
            service    = {
              name     = "service-3",
              path     = "/status/200",
            },
            regex_priority = 0,
          }
        }

        ngx.sleep(1)

        insert_routes {
          {
            strip_path = true,
            paths      = { "/status/(ab)c?" },
            service    = {
              name     = "service-4",
              path     = "/status/200",
            },
            regex_priority = 0,
          },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      it("depends on the regex_priority field", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/re",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("service-2", res.headers["kong-service-name"])
      end)

      it("depends on created_at if regex_priority is tie", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/ab",
          headers = { ["kong-debug"] = 1 },
        })
        assert.res_status(200, res)
        assert.equal("service-3", res.headers["kong-service-name"])
      end)
    end)

    describe("URI arguments (querystring)", function()

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        insert_routes {
          {
            hosts = { "mock_upstream" },
          },
        }

        assert(dao:run_migrations())

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes = insert_routes {
          {
            strip_path = true,
            paths      = { "/endel%C3%B8st" },
          },
          {
            strip_path = true,
            paths      = { "/foo/../bar" },
          },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        insert_routes {
          {
            paths      = { "/x/y/z", "/z/y/x" },
            strip_path = true,
          },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        insert_routes {
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
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes = insert_routes {
          {
            strip_path = true,
            paths      = { "/" },
          },
          {
            strip_path = true,
            paths      = { "/foobar" },
          },
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes = insert_routes {
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
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        routes = insert_routes {
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
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

    describe("trailing slash", function()
      local checks = {
        -- upstream url    paths            request path    expected path          strip path
        {  "/",            "/",            "/",            "/",                    true      },
        {  "/",            "/",            "/get/bar",     "/get/bar",             true      },
        {  "/",            "/",            "/get/bar/",    "/get/bar/",            true      },
        {  "/",            "/get/bar",     "/get/bar",     "/",                    true      },
        {  "/",            "/get/bar",     "/get/bar/",    "/",                    true      },
        {  "/get/bar",     "/",            "/",            "/get/bar",             true      },
        {  "/get/bar",     "/",            "/get/bar",     "/get/bar/get/bar",     true      },
        {  "/get/bar",     "/",            "/get/bar/",    "/get/bar/get/bar/",    true      },
        {  "/get/bar",     "/get/bar",     "/get/bar",     "/get/bar",             true      },
        {  "/get/bar",     "/get/bar",     "/get/bar/",    "/get/bar/",            true      },
        {  "/get/bar/",    "/",            "/",            "/get/bar/",            true      },
        {  "/get/bar/",    "/",            "/get/bar",     "/get/bar/get/bar",     true      },
        {  "/get/bar/",    "/",            "/get/bar/",    "/get/bar/get/bar/",    true      },
        {  "/get/bar/",    "/get/bar",     "/get/bar",     "/get/bar",             true      },
        {  "/get/bar/",    "/get/bar",     "/get/bar/",    "/get/bar/",            true      },
        {  "/",            "/",            "/",            "/",                    false     },
        {  "/",            "/",            "/get/bar",     "/get/bar",             false     },
        {  "/",            "/",            "/get/bar/",    "/get/bar/",            false     },
        {  "/",            "/get/bar",     "/get/bar",     "/get/bar",             false     },
        {  "/",            "/get/bar",     "/get/bar/",    "/get/bar/",            false     },
        {  "/get/bar",     "/",            "/",            "/get/bar",             false     },
        {  "/get/bar",     "/",            "/get/bar",     "/get/bar/get/bar",     false     },
        {  "/get/bar",     "/",            "/get/bar/",    "/get/bar/get/bar/",    false     },
        {  "/get/bar",     "/get/bar",     "/get/bar",     "/get/bar/get/bar",     false     },
        {  "/get/bar",     "/get/bar",     "/get/bar/",    "/get/bar/get/bar/",    false     },
        {  "/get/bar/",    "/",            "/",            "/get/bar/",            false     },
        {  "/get/bar/",    "/",            "/get/bar",     "/get/bar/get/bar",     false     },
        {  "/get/bar/",    "/",            "/get/bar/",    "/get/bar/get/bar/",    false     },
        {  "/get/bar/",    "/get/bar",     "/get/bar",     "/get/bar/get/bar",     false     },
        {  "/get/bar/",    "/get/bar",     "/get/bar/",    "/get/bar/get/bar/",    false     },
      }

      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        for i, args in ipairs(checks) do
          assert(insert_routes {
            {
              strip_path   = args[5],
              paths        = {
                args[2],
              },
              hosts        = {
                "localbin-" .. i .. ".com",
              },
              service = {
                name = "service-" .. i,
                path = args[1]
              }
            }
          })
        end

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
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

        local config = "(strip_path = n/a)"

        if args[5] == true then
          config = "(strip_path = on) "

        elseif args[5] == false then
          config = "(strip_path = off)"
        end

        it(config .. " is not appended to upstream url " .. args[1] ..
                     " (with uri "                       .. args[2] .. ")" ..
                     " when requesting "                 .. args[3],
          check(i, args[3], args[4]))
      end
    end)
  end)
end
