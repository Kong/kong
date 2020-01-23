local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("OpenResty phases [#" .. strategy .. "]", function()
    describe("rewrite_by_lua", function()
      describe("enabled on all routes", function()
        local admin_client
        local proxy_client

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
          })

          -- insert plugin-less route and a global plugin
          local service = bp.services:insert {
            name = "mock_upstream",
          }

          bp.routes:insert {
            protocols = { "http" },
            hosts     = { "mock_upstream" },
            service   = service,
          }

          bp.plugins:insert {
            name    = "rewriter",
            config  = {
              value = "global plugin",
            },
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          admin_client = helpers.admin_client()
          proxy_client = helpers.proxy_client()
        end)

        lazy_teardown(function()
          if admin_client then admin_client:close() end
          helpers.stop_kong(nil, true)
        end)

        it("runs", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host  = "mock_upstream",
            },
          })
          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("rewriter")
          assert.equal("global plugin", value)
        end)
      end)

      describe("enabled on a specific routes", function()
        local admin_client
        local proxy_client

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
          })

          -- route specific plugin
          local service = bp.services:insert {
            name = "mock_upstream",
          }

          local route = bp.routes:insert {
            hosts   = { "mock_upstream" },
            service = service,
          }

          bp.plugins:insert {
            route   = { id = route.id },
            service = { id = service.id },
            name    = "rewriter",
            config  = {
              value = "route-specific plugin",
            },
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template"
          }))

          admin_client = helpers.admin_client()
          proxy_client = helpers.proxy_client()
        end)

        lazy_teardown(function()
          if admin_client then admin_client:close() end
          helpers.stop_kong(nil, true)
        end)

        it("doesn't run", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host  = "mock_upstream",
            },
          })
          assert.response(res).has.status(200)
          assert.request(res).has.no.header("rewriter")
        end)
      end)

      describe("enabled on a specific Consumer", function()
        local admin_client
        local proxy_client

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
            "consumers",
            "keyauth_credentials",
          })

          -- consumer specific plugin
          local service = bp.services:insert {
            name = "mock_upstream",
          }

          local route = bp.routes:insert {
            protocols = { "http" },
            hosts     = { "mock_upstream" },
            service   = service,
          }

          bp.plugins:insert {
            name    = "key-auth",
            route   = { id = route.id },
            service = { id = service.id },
          }

          local consumer3 = bp.consumers:insert {
            username = "test-consumer-3",
          }

          bp.keyauth_credentials:insert {
            consumer = { id = consumer3.id },
            key      = "kong",
          }

          bp.plugins:insert {
            consumer = { id = consumer3.id },
            name     = "rewriter",
            config   = {
              value  = "consumer-specific plugin",
            },
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          admin_client = helpers.admin_client()
          proxy_client = helpers.proxy_client()
        end)

        lazy_teardown(function()
          if admin_client then admin_client:close() end
          helpers.stop_kong(nil, true)
        end)

        it("doesn't run", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              host   = "mock_upstream",
              apikey = "kong",
            },
          })
          assert.response(res).has.status(200)
          local value = assert.request(res).has.header("x-consumer-username")
          assert.equal("test-consumer-3", value)
          assert.request(res).has.no.header("rewriter")
        end)
      end)
    end)
  end)
end
