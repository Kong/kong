local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: http-log (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc, proxy_client_grpcs

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local service1 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        hosts   = { "http_logging.test" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http"
        }
      }

      local service1 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        hosts   = { "http_logging.test" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http"
        }
      }

      local service2 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route2 = bp.routes:insert {
        hosts   = { "https_logging.test" },
        service = service2
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "http-log",
        config   = {
          http_endpoint = "https://" .. helpers.mock_upstream_ssl_host
                                     .. ":"
                                     .. helpers.mock_upstream_ssl_port
                                     .. "/post_log/https"
        }
      }

      local service3 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route3 = bp.routes:insert {
        hosts   = { "http_basic_auth_logging.test" },
        service = service3
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. "testuser:testpassword@"
                                    .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_auth_log/basic_auth"
                                    .. "/testuser/testpassword"
        }
      }

      local route4 = bp.routes:insert {
        hosts   = { "http_queue_logging.test" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route4.id },
        name     = "http-log",
        config   = {
          queue_size = 5,
          flush_timeout = 0.1,
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http_queue"
        }
      }

      local route6 = bp.routes:insert {
        hosts   = { "https_logging_faulty.test" },
        service = service2
      }

      bp.plugins:insert {
        route = { id = route6.id },
        name     = "http-log",
        config   = {
          http_endpoint = "https://" .. helpers.mock_upstream_ssl_host
                                     .. ":"
                                     .. helpers.mock_upstream_ssl_port
                                     .. "/delay/5",
          timeout = 1
        }
      }

      local test_error_log_path = helpers.test_conf.nginx_err_logs
      os.execute(":> " .. test_error_log_path)

      local grpc_service = assert(bp.services:insert {
        name = "grpc-service",
        url = "grpc://localhost:15002",
      })

      local route7 = assert(bp.routes:insert {
        service = grpc_service,
        protocols = { "grpc" },
        hosts = { "http_logging_grpc.test" },
      })

      bp.plugins:insert {
        route = { id = route7.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/grpc",
          timeout = 1
        },
      }

      local grpcs_service = assert(bp.services:insert {
        name = "grpcs-service",
        url = "grpcs://localhost:15003",
      })

      local route8 = assert(bp.routes:insert {
        service = grpcs_service,
        protocols = { "grpcs" },
        hosts = { "http_logging_grpcs.test" },
      })

      bp.plugins:insert {
        route = { id = route8.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/grpcs",
          timeout = 1
        },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client_grpc = helpers.proxy_client_grpc()
      proxy_client_grpcs = helpers.proxy_client_grpcs()
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

    it("logs to HTTP", function()
      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "http_logging.test"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/http",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)

        if #body.entries == 1 then
          assert.same("127.0.0.1", body.entries[1].client_ip)
          return true
        end
      end, 10)
    end)

    it("logs to HTTP (#grpc)", function()
      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "http_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/grpc",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)

        if #body.entries == 1 then
          assert.same("127.0.0.1", body.entries[1].client_ip)
          assert.same("application/grpc", body.entries[1].request.headers["content-type"])
          assert.same("application/grpc", body.entries[1].response.headers["content-type"])
          return true
        end
      end, 10)
    end)

    it("logs to HTTP (#grpcs)", function()
      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "http_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/grpcs",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)

        if #body.entries == 1 then
          assert.same("127.0.0.1", body.entries[1].client_ip)
          assert.same("application/grpc", body.entries[1].request.headers["content-type"])
          assert.same("application/grpc", body.entries[1].response.headers["content-type"])
          return true
        end
      end, 10)
    end)

    it("logs to HTTPS", function()
      local res = assert(proxy_client:send({
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "https_logging.test"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/https",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.entries == 1 then
          assert.same("127.0.0.1", body.entries[1].client_ip)
          return true
        end
      end, 10)
    end)

    it("gracefully handles layer 4 failures", function()
      -- setup: cleanup logs
      local test_error_log_path = helpers.test_conf.nginx_err_logs
      os.execute(":> " .. test_error_log_path)

      local res = assert(proxy_client:send({
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "https_logging_faulty.test"
        }
      }))
      assert.res_status(200, res)

      local pl_file = require "pl.file"

      helpers.wait_until(function()
        -- Assertion: there should be no [error] resulting from attempting
        -- to reference a nil res on res:body() calls within the http-log plugin

        local logs = pl_file.read(test_error_log_path)
        local found = false

        for line in logs:gmatch("[^\r\n]+") do
          if line:find("failed to process entries: .* " ..
                       helpers.mock_upstream_ssl_host .. ":" ..
                       helpers.mock_upstream_ssl_port .. ": timeout")
          then
            found = true

          else
            assert.not_match("[error]", line, nil, true)
          end
        end

        if found then
            return true
        end
      end, 2)
    end)

    it("adds authorization if userinfo is present", function()
      local res = assert(proxy_client:send({
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "http_basic_auth_logging.test"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/basic_auth",
          headers = {
            Accept = "application/json"
          }
        })

        local body = cjson.decode(assert.res_status(200, res))

        if #body.entries == 1 then
          for name, value in pairs(body.entries[1].log_req_headers) do
            if name == "authorization" then
              assert.same("Basic dGVzdHVzZXI6dGVzdHBhc3N3b3Jk", value)
              return true
            end
          end
        end
      end, 10)
    end)
  end)

  -- test both with a single worker for a deterministic test,
  -- and with multiple workers for a concurrency test
  for _, workers in ipairs({1, 4}) do
    describe("Plugin: http-log (log) queue (worker_processes = " .. workers .. ") [#" .. strategy .. "]", function()
      local proxy_client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local service = bp.services:insert{
          protocol = "http",
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_port,
        }

        local route = bp.routes:insert {
          hosts   = { "http_queue_logging.test" },
          service = service
        }

        bp.plugins:insert {
          route = { id = route.id },
          name     = "http-log",
          config   = {
            queue_size = 5,
            flush_timeout = 0.1,
            http_endpoint = "http://" .. helpers.mock_upstream_host
                                      .. ":"
                                      .. helpers.mock_upstream_port
                                      .. "/post_log/http_queue"
          }
        }

        local route2 = bp.routes:insert {
          hosts   = { "http_queue_logging2.test" },
          service = service
        }

        bp.plugins:insert {
          route = { id = route2.id },
          name     = "http-log",
          config   = {
            queue_size = 5,
            flush_timeout = 0.1,
            http_endpoint = "http://" .. helpers.mock_upstream_host
                                      .. ":"
                                      .. helpers.mock_upstream_port
                                      .. "/post_log/http_queue2"
          }
        }

        assert(helpers.start_kong({
          database = strategy,
          nginx_worker_processes = workers,
        }))

        assert(helpers.start_kong({
          database = strategy,
          prefix = "servroot2",
          admin_listen = "127.0.0.1:9010",
          proxy_listen = "127.0.0.1:9011",
          stream_listen = "off",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          nginx_worker_processes = 1,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        helpers.stop_kong("servroot2")
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end
      end)


      local function reset_log(logname)
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        assert(client:send {
          method  = "DELETE",
          path    = "/reset_log/" .. logname,
          headers = {
            Accept = "application/json"
          }
        })
        client:close()
      end


      it("logs to HTTP with a buffer", function()
        reset_log("http_queue")

        local n = 200

        for i = 1, n do
          local client = helpers.proxy_client()
          local res = assert(client:send({
            method = "GET",
            path = "/status/" .. tostring(200 + (i % 10)),
            headers = {
              ["Host"] = "http_queue_logging.test"
            }
          }))
          assert.res_status(200 + (i % 10), res)
          client:close()
        end

        helpers.wait_until(function()
          local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                    helpers.mock_upstream_port))
          local res = assert(client:send {
            method  = "GET",
            path    = "/count_log/http_queue",
            headers = {
              Accept = "application/json"
            }
          })

          local count = assert.res_status(200, res)
          client:close()

          if tonumber(count, 10) >= n then
            return true
          end
        end, 60)
      end)

      it("does not mix buffers", function()
        reset_log("http_queue")
        reset_log("http_queue2")

        local n = 200

        for i = 1, n do
          local client = helpers.proxy_client()
          local res = assert(client:send({
            method = "GET",
            path = "/status/" .. tostring(200 + (i % 10)),
            headers = {
              ["Host"] = "http_queue_logging.test"
            }
          }))
          assert.res_status(200 + (i % 10), res)
          client:close()

          client = helpers.proxy_client()
          res = assert(client:send({
            method = "GET",
            path = "/status/" .. tostring(300 + (i % 10)),
            headers = {
              ["Host"] = "http_queue_logging2.test"
            }
          }))
          assert.res_status(300 + (i % 10), res)
          client:close()
        end

        helpers.wait_until(function()
          local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                    helpers.mock_upstream_port))
          local res = assert(client:send {
            method  = "GET",
            path    = "/read_log/http_queue",
            headers = {
              Accept = "application/json"
            }
          })
          local raw = assert.res_status(200, res)
          local body = cjson.decode(raw)
          client:close()

          local client2 = assert(helpers.http_client(helpers.mock_upstream_host,
                                                     helpers.mock_upstream_port))
          local res2 = assert(client2:send {
            method  = "GET",
            path    = "/read_log/http_queue2",
            headers = {
              Accept = "application/json"
            }
          })
          local raw2 = assert.res_status(200, res2)
          local body2 = cjson.decode(raw2)
          client2:close()

          if body.count < n or body2.count < n then
            return false
          end

          table.sort(body.entries, function(a, b)
            return a.response.status < b.response.status
          end)

          local i = 0
          for _, entry in ipairs(body.entries) do
            assert.same("127.0.0.1", entry.client_ip)
            assert.same(200 + math.floor(i / (n / 10)), entry.response.status)
            i = i + 1
          end

          if i ~= n then
            return false
          end

          table.sort(body2.entries, function(a, b)
            return a.response.status < b.response.status
          end)

          i = 0
          for _, entry in ipairs(body2.entries) do
            assert.same("127.0.0.1", entry.client_ip)
            assert.same(300 + math.floor(i / (n / 10)), entry.response.status)
            i = i + 1
          end

          if i ~= n then
            return false
          end

          return true
        end, 60)
      end)
    end)

  end


  describe("Plugin: http-log (log) enabled globally [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      bp.plugins:insert {
        name     = "http-log",
        config   = {
          http_endpoint = "http://" .. helpers.mock_upstream_host
                                    .. ":"
                                    .. helpers.mock_upstream_port
                                    .. "/post_log/http"
        }
      }

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

    it("executes successfully when route does not exist", function()
      local res = assert(proxy_client:send({
        method  = "GET",
        path    = "/nonexistant/proxy/path",
        headers = {
          ["Host"] = "http_no_exist.test"
        }
      }))
      assert.res_status(404, res)

      --Assert that the plugin executed and has 1 log entry
      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host,
                                                  helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/http",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.entries == 1 then
          assert.same("127.0.0.1", body.entries[1].client_ip)
          return true
        end
      end, 10)

      -- Assertion: there should be no [error], including no error
      -- resulting from attempting to reference the id on
      -- a route when no such value exists after http-log execution

      local pl_file = require "pl.file"
      local logs = pl_file.read(helpers.test_conf.nginx_err_logs)

      for line in logs:gmatch("[^\r\n]+") do
        assert.not_match("[error]", line, nil, true)
      end
    end)
  end)
end
