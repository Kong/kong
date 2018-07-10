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
        route_id = route1.id,
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
        route_id = route1.id,
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
        route_id = route2.id,
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
        route_id = route3.id,
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
      end, 5)
    end, 10)

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
end
