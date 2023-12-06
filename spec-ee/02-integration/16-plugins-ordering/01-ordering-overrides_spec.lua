-- this software is copyright kong inc. and its licensors.
-- use of the software is subject to the agreement between your organization
-- and kong inc. if there is no such agreement, use is governed by and
-- subject to the terms of the kong master software license agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ end of license 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local proxy_client = helpers.proxy_client
local admin_client = helpers.admin_client
local cjson = require("cjson")

local fmt = string.format

local function GET(url, opts, res_status)
  ngx.sleep(0.010)

  local client   = proxy_client()
  local res, err = client:get(url, opts)
  if not res then
    client:close()
    return nil, err
  end

  local body, err = assert.res_status(res_status, res)
  if not body then
    return nil, err
  end

  client:close()

  return res, body
end

for _, strategy in helpers.all_strategies({ "postgres", "off" }) do
  describe("Dynamic Plugin Ordering #" .. strategy, function()
    local bp, db

    lazy_setup(function()
      helpers.kill_all()
      assert(conf_loader(nil, {
      }))

      bp, db = helpers.get_db_utils(strategy, { "plugins",
        "routes" }, { "key-auth", "rate-limiting" })


      local consumer1 = bp.consumers:insert {
        custom_id = "provider_123",
      }

      bp.keyauth_credentials:insert {
        key      = "apikey122",
        consumer = { id = consumer1.id },
      }

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      bp.plugins:insert({
        name = "rate-limiting",
        route = { id = route1.id },
        config = {
          minute = 6,
          policy = "local"
        }
      })

      -- An unused route within the same workspace must not influence any other plugin instances
      local route2 = bp.routes:insert {
        hosts = { "test2.test" },
      }

      bp.plugins:insert({
        name = "rate-limiting",
        route = { id = route2.id },
        config = {
          minute = 6,
          policy = "local"
        },
        ordering = {
          before = {
            access = {
              "key-auth"
            }
          },
        }
      })

      bp.key_auth_plugins:insert()

      local decl = helpers.make_yaml_file [[
        _transform: false
        _format_version: '2.1'
        consumers:
        - custom_id: provider_123
          id: 21a3f78d-4610-4ffc-94ae-0567017217f5
          username: consumer-username-1
        routes:
        - name: default-route
          hosts:
          - test1.test
          id: 17547fe7-8768-4d17-9feb-f8f732bdfe54
        - name: route-2
          hosts:
          - test2.test
          id: 549d31f1-3671-4487-b50b-e0cfcbd495dc
        plugins:
        - enabled: true
          name: rate-limiting
          route: 549d31f1-3671-4487-b50b-e0cfcbd495dc
          config:
            policy: local
            minute: 6
          id: 1c62feee-697d-4334-9537-240bd493cfa0
          order:
            before:
              access:
              - key-auth
        - enabled: true
          name: key-auth
          route: 549d31f1-3671-4487-b50b-e0cfcbd495dc
          config:
            run_on_preflight: true
            key_in_header: true
            key_in_query: true
            key_in_body: false
            key_names:
            - apikey
          id: 5b664778-4932-48b7-b1cf-01f2304f41fa
        - enabled: true
          name: rate-limiting
          route: 17547fe7-8768-4d17-9feb-f8f732bdfe54
          config:
            policy: local
            minute: 6
          id: dbd9cc3b-0e31-4bdd-86f3-23553e89b19a
        keyauth_credentials:
        - id: 050de7bd-e993-4990-bebf-00fde4e579c7
          consumer: 21a3f78d-4610-4ffc-94ae-0567017217f5
          ws_id: af94e06d-1dfc-4c76-a343-d28c2f53b4ed
          key: apikey122
      ]]
      assert(helpers.start_kong {
        plugins = "bundled,rate-limiting,key-auth",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy ~= "off" and decl or nil,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      if strategy ~= "off" then
        assert(db:truncate("ratelimiting_metrics"))
      end
    end)

    it("Executes in correct order -> Authorization before rate-limiting", function()
      -- verify that key-auth is executed _before_ rate-limiting
      -- In unit-tests we already verify the sorting order that defines the execution order. In a integration test scenario
      -- we can send requests _with_ a valid apikey until we get rate-limited and then send requests _without_ a valid apikey
      -- and expect to still get rate-limited
      for i = 1, 6 do
        local res = GET("/status/200?apikey=apikey122", {
          headers = { Host = fmt("test1.test") },
        }, 200)

        assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
        assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
        assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
        local reset = tonumber(res.headers["ratelimit-reset"])
        assert.equal(true, reset <= 60 and reset > 0)

        -- wait for zero-delay timer
        helpers.wait_timer("rate-limiting", true, "all-finish")
      end
      local res = GET("/status/200?apikey=ABSOLUTELY_INVALID", {
        headers = { Host = fmt("test1.test") },
      }, 401)
      -- We expect that we are not Autohorized to access the protected endpoint even we have reached our
      -- limit of requests.
      assert.are.same("Unauthorized", res.reason)

    end)

    it("Executes in changed order -> rate-limiting before authn", function()
      for i = 1, 6 do
        local res = GET("/status/200?apikey=apikey122", {
          headers = { Host = fmt("test2.test") },
        }, 200)

        assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
        assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
        assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
        local reset = tonumber(res.headers["ratelimit-reset"])
        assert.equal(true, reset <= 60 and reset > 0)

        -- wait for zero-delay timer
        helpers.wait_timer("rate-limiting", true, "all-finish")
      end
      local res = GET("/status/200?apikey=ABSOLUTELY_INVALID", {
        headers = { Host = fmt("test2.test") },
      }, 429)
      -- We expect that we are not authenticataed as we have reached the limit of requests.
      assert.are.same("Too Many Requests", res.reason)
    end)
  end)

  describe("Dynamic Plugin Ordering request-termination - request-transformation" .. strategy, function()
    local bp

    lazy_setup(function()
      helpers.kill_all()
      assert(conf_loader(nil, {
        plugins = "request-transformer, request-termination",
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
      })

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      bp.plugins:insert({
        name = "request-transformer",
        route = { id = route1.id },
        config = {
          remove = {
            headers = {
              "x-toremove",
            } }
        }
      })
      bp.plugins:insert({
        name = "request-termination",
        route = { id = route1.id },
        config = {
          echo = true,
        },
      })

      local route2 = bp.routes:insert {
        hosts = { "test2.test" },
      }

      bp.plugins:insert({
        name = "request-transformer",
        route = { id = route2.id },
        config = {
          remove = {
            headers = {
              "x-removeme",
            } }
        },
        ordering = {
          before = {
            access = {
              "request-termination"
            }
          }
        }
      })

      bp.plugins:insert({
        name = "request-termination",
        route = { id = route2.id },
        config = {
          echo = true
        },
      })

      assert(helpers.start_kong {
        plugins = "bundled, request-transformer, request-termination",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)


    it("Executes in default order", function()
      -- request-termination -> request-transformer
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test1.test",
          ["x-removeme"] = "foo",
        },
      })
      -- assert that request-transformer did run
      local body = assert.res_status(503, res)
      local json = cjson.decode(body)
      -- assert that no headers are changed/removed as request-termination ran before the transformer
      assert.are.same("Service unavailable", json.message)
      assert.are.same("foo", json.request.headers["x-removeme"])
    end)

    it("Executes in changed order", function()
      -- request-transformer -> request-termination
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test2.test",
          ["x-removeme"] = "foo",
        },
      })

      local body = assert.res_status(503, res)
      local json = cjson.decode(body)
      -- assert that request-transformer did run before the request-termination
      assert.are.same(nil, json.request.headers["x-removeme"])
    end)

  end)

  describe("Dynamic Plugin Ordering forward-proxy " .. strategy, function()
    local bp

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = "bundled,forward-proxy,canary",
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
      }, { "forward-proxy", "canary" })

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "test2.test" },
      }

      bp.plugins:insert({
        name = "forward-proxy",
        route = { id = route1.id },
        config = {
          http_proxy_host = helpers.mock_upstream_host,
          http_proxy_port = helpers.mock_upstream_port,
        }
      })

      bp.plugins:insert({
        name = "forward-proxy",
        route = { id = route2.id },
        config = {
          http_proxy_host = helpers.mock_upstream_host,
          http_proxy_port = helpers.mock_upstream_port,
        }
      })

      bp.plugins:insert({
        name = "canary",
        route = { id = route2.id },
        config = {
          percentage = 100,
          upstream_host = "canary",
          upstream_port = 25000
        },
        ordering = {
          before = {
            access = {
              "forward-proxy"
            }
          }
        }
      })

      assert(helpers.start_kong {
        plugins = "bundled,forward-proxy,canary",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)


    it("forward-proxy before canary (default order)", function()
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test1.test",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("test1.test", json.headers["x-forwarded-host"])
      assert.equal("9000", json.headers["x-forwarded-port"])
      assert.equal(helpers.mock_upstream_host .. ":" .. tostring(helpers.mock_upstream_port), json.headers["host"])
    end)

    it("canary before forward-proxy (changed order)", function()
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test2.test",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("test2.test", json.headers["x-forwarded-host"])
      assert.equal("9000", json.headers["x-forwarded-port"])
      assert.equal("canary:25000", json.headers["host"])
    end)
  end)

  pending("Dynamic Plugin Ordering circular dependency -- This should fail! " .. strategy, function()
    local bp

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = "bundled,key-auth,rate-limiting",
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
      })

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      bp.plugins:insert({
        name = "key-auth",
        route = { id = route1.id },
        ordering = {
          before = {
            access = {
              "rate-limiting"
            }
          }
        },
        config = {
          key_names = { "foo" }
        }
      })

      bp.plugins:insert({
        name = "rate-limiting",
        route = { id = route1.id },
        ordering = {
          before = {
            access = {
              "key-auth"
            }
          }
        },
        config = {
          second = 5
        }
      })

      assert(helpers.start_kong {
        plugins = "bundled,key-auth,rate-limiting",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)
  end)

  describe("FTI-2806 - Consistent behavior for multiple auth plugins" .. strategy, function()
    local bp

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = "bundled,key-auth,basic-auth",
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "consumers",
        "keyauth_credentials",
        "basicauth_credentials",
      })

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      bp.keyauth_credentials:insert {
        key = "duck",
        consumer = { id = consumer.id },
      }

      bp.plugins:insert({
        name = "key-auth",
        route = { id = route1.id },
        config = {
          key_names = { "apikey" }
        }
      })

      bp.basicauth_credentials:insert {
        username = "bob",
        password = "kong",
        consumer = { id = consumer.id },
      }

      bp.plugins:insert({
        name = "basic-auth",
        route = { id = route1.id },
        ordering = {
          after = {
            access = {
              "key-auth"
            }
          }
        },
      })

      assert(helpers.start_kong {
        plugins = "bundled,key-auth,rate-limiting",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("must block acceess when credentials are missing", function()
      for _ = 1, 100 do
        local res = assert(proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            host = "test1.test",
            apikey = "duck"
          }
        })
        assert.res_status(401, res)
        assert.are.same("Unauthorized", res.reason)
      end
    end)

    it("must pass when credentials are present", function()
      for _ = 1, 100 do
        local res = assert(proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            host = "test1.test",
            apikey = "duck",
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
          }
        })
        assert.res_status(200, res)
      end
    end)
  end)

  describe("FTI-2803 - Deleting plugins that have a depedency on them" .. strategy, function()
    local bp
    local bauth_plugin

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = "rate-limiting-advanced,basic-auth",
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "consumers",
        "basicauth_credentials",
      }, { "rate-limiting-advanced" })

      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      bp.plugins:insert({
        name = "rate-limiting-advanced",
        route = { id = route1.id },
        config = {
          window_size = { 6 },
          limit = { 3 },
          strategy = "local"
        },
        ordering = {
          after = {
            access = {
              "basic-auth"
            }
          }
        },
      })

      bp.basicauth_credentials:insert {
        username = "bob",
        password = "kong",
        consumer = { id = consumer.id },
      }

      bauth_plugin = bp.plugins:insert({
        name = "basic-auth",
        route = { id = route1.id },
      })

      assert(helpers.start_kong {
        plugins = "bundled,basic-auth,rate-limiting-advanced",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("must not stacktrace when dependencies are invalid", function()
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test1.test",
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
        }
      })
      assert.res_status(200, res)
      local res = assert(admin_client():send {
        method = "DELETE",
        path = "/plugins/" .. bauth_plugin.id,
      })
      assert.res_status(204, res)
      local res2 = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test1.test",
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
        }
      })
      assert.res_status(200, res2)
    end)
  end)

  describe("FTI-2821 request transformation" .. strategy, function()
    local bp

    lazy_setup(function()
      helpers.kill_all()

      assert(conf_loader(nil, {
        plugins = { "request-transformer-advanced", "basic-auth", "key-auth" }
      }))

      bp, _ = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "consumers",
        "basicauth_credentials",
      }, { "request-transformer-advanced" })

      local route = bp.routes:insert {
        hosts = { "test1.test" },
      }

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      bp.plugins:insert({
        name = "request-transformer-advanced",
        route = { id = route.id },
        config = {
          add = {
            headers = {
              "Authorization:Basic Ym9iOmtvbmc=",
              "x-apikey:duck"
            }
          }
        },
        ordering = {
          before = {
            access = {
              "basic-auth",
              "key-auth"
            }
          }
        },
      })

      bp.basicauth_credentials:insert {
        username = "bob",
        password = "kong",
        consumer = { id = consumer.id },
      }

      bp.plugins:insert({
        name = "key-auth",
        route = { id = route.id },
        ordering = {
          after = {
            access = {
              "basic-auth"
            }
          }
        },
        config = {
          key_names = { "x-apikey" },
          key_in_header = true
        }
      })

      bp.keyauth_credentials:insert {
        key = "duck",
        consumer = { id = consumer.id },
      }

      -- global plugin
      bp.plugins:insert({
        name = "basic-auth",
      })

      assert(helpers.start_kong {
        plugins = "bundled,request-transformer-advanced",
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("Requests can be transformed and auth passes", function()
      local res = assert(proxy_client():send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test1.test",
        }
      })
      assert.res_status(200, res)
    end)
  end)
end
