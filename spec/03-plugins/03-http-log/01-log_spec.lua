local cjson      = require "cjson"
local socket     = require "socket"
local helpers    = require "spec.helpers"


local mockbin_ip = socket.dns.toip("mockbin.org")


local function create_mock_bin()
  local proxy_client = assert(helpers.http_client(mockbin_ip, 80))

  local res = assert(proxy_client:send({
    method  = "POST",
    path    = "/bin/create",
    body    = '{"status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1", "headers": [], "cookies": [], "content": { "mimeType" : "application/json" }, "redirectURL": "", "headersSize": 0, "bodySize": 0}',
    headers = {
      Host  = "mockbin.org",
      ["Content-Type"] = "application/json"
    }
  }))

  local body = assert.res_status(201, res)

  return body:sub(2, body:len() - 1)
end


local mock_bin_http            = create_mock_bin()
local mock_bin_https           = create_mock_bin()
local mock_bin_http_basic_auth = create_mock_bin()


for _, strategy in helpers.each_strategy() do
  pending("Plugin: http-log (log) [#" .. strategy .. "]", function()
    -- Pending: at the time of this change, mockbin.com's behavior with bins
    -- seems to be broken.
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local service1 = bp.services:insert{
        protocol = "http",
        host     = "mockbin.com",
        port     = 80,
      }

      local route1 = bp.routes:insert {
        hosts   = { "http_logging.com" },
        service = service1
      }

      bp.plugins:insert {
        route_id = route1.id,
        name     = "http-log",
        config   = {
          http_endpoint = "http://mockbin.org/bin/" .. mock_bin_http
        }
      }

      local service2 = bp.services:insert{
        protocol = "http",
        host     = "mockbin.com",
        port     = 80,
      }

      local route2 = bp.routes:insert {
        hosts   = { "http_logging.com" },
        service = service2
      }

      bp.plugins:insert {
        route_id = route2.id,
        name     = "http-log",
        config   = {
          http_endpoint = "https://mockbin.org/bin/" .. mock_bin_https
        }
      }

      local service3 = bp.services:insert{
        protocol = "http",
        host     = "mockbin.com",
        port     = 80,
      }

      local route3 = bp.routes:insert {
        hosts   = { "http_basic_auth_logging.com" },
        service = service3
      }

      bp.plugins:insert {
        route_id = route3.id,
        name     = "http-log",
        config   = {
          http_endpoint = "http://testuser:testpassword@mockbin.org/bin/" .. mock_bin_http_basic_auth
        }
      }

      assert(helpers.start_kong({
        database = strategy,
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
          ["Host"] = "http_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(mockbin_ip, 80))
        local res = assert(client:send {
          method  = "GET",
          path    = "/bin/" .. mock_bin_http .. "/log",
          headers = {
            Host   = "mockbin.org",
            Accept = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
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
          ["Host"] = "https_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(mockbin_ip, 80))
        local res = assert(client:send {
          method  = "GET",
          path    = "/bin/" .. mock_bin_https .. "/log",
          headers = {
            Host   = "mockbin.org",
            Accept = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
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
          ["Host"] = "http_basic_auth_logging.com"
        }
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local client = assert(helpers.http_client(mockbin_ip, 80))
        local res = assert(client:send {
          method  = "GET",
          path    = "/bin/" .. mock_bin_http_basic_auth .. "/log",
          headers = {
            Host   = "mockbin.org",
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
