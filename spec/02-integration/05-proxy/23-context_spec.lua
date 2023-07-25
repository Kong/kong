local helpers = require "spec.helpers"
local null = ngx.null
local atc_compat = require "kong.router.compat"


local function reload_router(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  helpers.setenv("KONG_ROUTER_FLAVOR", flavor)

  package.loaded["spec.helpers"] = nil
  package.loaded["kong.global"] = nil
  package.loaded["kong.cache"] = nil
  package.loaded["kong.db"] = nil
  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  helpers = require "spec.helpers"

  helpers.unsetenv("KONG_ROUTER_FLAVOR")
end


local function gen_route(flavor, r)
  if flavor ~= "expressions" then
    return r
  end

  r.expression = atc_compat.get_expression(r)
  r.priority = tonumber(atc_compat._get_priority(r))

  r.paths = nil
  r.destinations = nil

  return r
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, strategy in helpers.each_strategy() do
  describe("Context Tests [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    describe("[http]", function()
      reload_router(flavor)

      local proxy_client
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, {
          "ctx-tests",
          "ctx-tests-response",
        })

        local unbuff_route = bp.routes:insert(gen_route(flavor, {
          paths   = { "/" },
        }))

        bp.plugins:insert {
          name = "ctx-tests",
          route = { id = unbuff_route.id },
          service = null,
          consumer = null,
          protocols = {
            "http", "https", "tcp", "tls", "grpc", "grpcs"
          },
          config = {
            buffered = false,
          }
        }

        local buffered_route = bp.routes:insert(gen_route(flavor, {
          paths   = { "/buffered" },
        }))

        bp.plugins:insert {
          name = "ctx-tests",
          route = { id = buffered_route.id },
          service = null,
          consumer = null,
          protocols = {
            "http", "https", "tcp", "tls", "grpc", "grpcs"
          },
          config = {
            buffered = true,
          }
        }

        local response_route = bp.routes:insert(gen_route(flavor, {
          paths = { "/response" },
        }))

        bp.plugins:insert {
          name = "ctx-tests-response",
          route = { id = response_route.id },
          service = null,
          consumer = null,
          protocols = {
            "http", "https", "tcp", "tls", "grpc", "grpcs"
          },
          config = {
            buffered = false,
          }
        }

        assert(helpers.start_kong({
          router_flavor = flavor,
          database      = strategy,
          plugins       = "bundled,ctx-tests,ctx-tests-response",
          nginx_conf    = "spec/fixtures/custom_nginx.template",
          stream_listen = "off",
          admin_listen  = "off",
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

      it("context values are correctly calculated", function()
        local res = proxy_client:get("/status/231")
        assert.truthy(res)
        assert.res_status(231, res)

        assert.logfile().has.no.line("[ctx-tests]", true)
      end)

      it("context values are correctly calculated (buffered)", function()
        local res = assert(proxy_client:get("/buffered/status/232"))
        assert.res_status(232, res)

        assert.logfile().has.no.line("[ctx-tests]", true)
      end)

      it("context values are correctly calculated (response)", function()
        local res = assert(proxy_client:get("/response/status/233"))
        assert.res_status(233, res)

        assert.logfile().has.no.line("[ctx-tests]", true)
      end)

      it("can run unbuffered request after a \"response\" one", function()
        local res = assert(proxy_client:get("/response/status/234"))
        assert.res_status(234, res)

        assert.logfile().has.no.line("[ctx-tests]", true)

        local res = proxy_client:get("/status/235")
        assert.truthy(res)
        assert.res_status(235, res)

        assert.logfile().has.no.line("[ctx-tests]", true)
      end)
    end)

    if strategy ~= "off" then
      describe("[stream]", function()
        reload_router(flavor)

        local MESSAGE = "echo, ping, pong. echo, ping, pong. echo, ping, pong.\n"
        local tcp_client
        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
          }, {
            "ctx-tests",
          })

          local service = assert(bp.services:insert {
            host     = helpers.mock_upstream_host,
            port     = helpers.mock_upstream_stream_port,
            protocol = "tcp",
          })

          assert(bp.routes:insert(gen_route(flavor, {
            destinations = {
              { port = 19000 },
            },
            protocols = {
              "tcp",
            },
            service = service,
          })))

          bp.plugins:insert {
            name = "ctx-tests",
            route = null,
            service = null,
            consumer = null,
            protocols = {
              "http", "https", "tcp", "tls", "grpc", "grpcs"
            },
          }

          assert(helpers.start_kong({
            router_flavor = flavor,
            database      = strategy,
            stream_listen = helpers.get_proxy_ip(false) .. ":19000",
            plugins       = "bundled,ctx-tests",
            nginx_conf    = "spec/fixtures/custom_nginx.template",
            proxy_listen  = "off",
            admin_listen  = "off",
          }))
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          tcp_client = ngx.socket.tcp()
          assert(tcp_client:connect(helpers.get_proxy_ip(false), 19000))
        end)

        it("context values are correctly calculated", function()
          -- TODO: we need to get rid of the next line!
          assert(tcp_client:send(MESSAGE))
          local body = assert(tcp_client:receive("*a"))
          assert.equal(MESSAGE, body)
          assert(tcp_client:close())

          assert.logfile().has.no.line("[ctx-tests]", true)
        end)
      end)
    end
  end)
end
end   -- for flavor
