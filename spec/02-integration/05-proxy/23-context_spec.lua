local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local null = ngx.null


for _, strategy in helpers.each_strategy() do
  describe("Context Tests [#" .. strategy .. "]", function()
    describe("[http]", function()
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

        local unbuff_route = bp.routes:insert {
          paths   = { "/" },
        }

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

        local buffered_route = bp.routes:insert {
          paths   = { "/buffered" },
        }

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

        local response_route = bp.routes:insert {
          paths = { "/response" },
        }

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

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("[ctx-tests]", err_log, nil, true)
      end)

      it("context values are correctly calculated (buffered)", function()
        local res = assert(proxy_client:get("/buffered/status/232"))
        assert.res_status(232, res)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("[ctx-tests]", err_log, nil, true)
      end)

      it("context values are correctly calculated (response)", function()
        local res = assert(proxy_client:get("/response/status/233"))
        assert.res_status(233, res)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("[ctx-tests]", err_log, nil, true)
      end)

      it("can run unbuffered request after a \"response\" one", function()
        local res = assert(proxy_client:get("/response/status/234"))
        assert.res_status(234, res)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("[ctx-tests]", err_log, nil, true)

        local res = proxy_client:get("/status/235")
        assert.truthy(res)
        assert.res_status(235, res)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.not_matches("[ctx-tests]", err_log, nil, true)
      end)
    end)

    if strategy ~= "off" then
      describe("[stream]", function()
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

          assert(bp.routes:insert {
            destinations = {
              { port = 19000 },
            },
            protocols = {
              "tcp",
            },
            service = service,
          })

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

          local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
          assert.not_matches("[ctx-tests]", err_log, nil, true)
        end)
      end)
    end
  end)
end
