local cjson      = require "cjson"
local helpers    = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: http-log (log) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

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
                                     .. "/delay/1",
          timeout = 1
        }
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    teardown(function()
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
        local client = assert(helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/http",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.log.entries == 1 then
          local log_message = cjson.decode(body.log.entries[1].request.postData.text)
          assert.same("127.0.0.1", log_message.client_ip)
          return true
        end
      end, 10)
    end)

    it("logs to HTTP with a buffer", function()
      for i = 1, 10 do
        local client = helpers.proxy_client()
        local res = assert(client:send({
          method = "GET",
          path = "/status/" .. tostring(200 + i),
          headers = {
            ["Host"] = "http_queue_logging.test"
          }
        }))
        assert.res_status(200 + i, res)
        client:close()
      end

      helpers.wait_until(function()
        local client = assert(helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/http_queue",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.log.entries ~= 2 then
          return false
        end
        local status = 200
        for _, entry in ipairs(body.log.entries) do
          local json = cjson.decode(entry.request.postData.text)
          if #json ~= 5 then
            return false
          end
          for _, item in ipairs(json) do
            assert.same("127.0.0.1", item.client_ip)
            status = status + 1
            assert.same(status, item.response.status)
          end
        end
        return true
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
        local client = assert(helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/https",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.log.entries == 1 then
          local log_message = cjson.decode(body.log.entries[1].request.postData.text)
          assert.same("127.0.0.1", log_message.client_ip)
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

      -- Assertion: there should be no [error], including no error
      -- resulting from attempting to reference a nil res on
      -- res:body() calls within the http-log plugin

      local pl_file = require "pl.file"
      local logs = pl_file.read(test_error_log_path)

      for line in logs:gmatch("[^\r\n]+") do
        assert.not_match("[error]", line, nil, true)
      end
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
        local client = assert(helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/basic_auth",
          headers = {
            Accept = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        if #body.log.entries == 1 then
          for _, value in pairs(body.log.entries[1].request.headers) do
            if value.name == "authorization" then
              assert.same("Basic dGVzdHVzZXI6dGVzdHBhc3N3b3Jk", value.value)
              return true
            end
          end
        end
      end, 10)
    end)
  end)

  describe("enabled globally", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy)

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
        local client = assert(helpers.http_client(helpers.mock_upstream_host, helpers.mock_upstream_port))
        local res = assert(client:send {
          method  = "GET",
          path    = "/read_log/http",
          headers = {
            Accept = "application/json"
          }
        })
        local raw = assert.res_status(200, res)
        local body = cjson.decode(raw)
        if #body.log.entries == 1 then
          local log_message = cjson.decode(body.log.entries[1].request.postData.text)
          assert.same("127.0.0.1", log_message.client_ip)
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