local cjson = require "cjson"
local socket = require "socket"
local helpers = require "spec.helpers"

local mockbin_ip = socket.dns.toip("mockbin.org")

local function create_mock_bin()
  local client = assert(helpers.http_client(mockbin_ip, 80))
  local res = assert(client:send({
    method = "POST",
    path = "/bin/create",
    body = '{"status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1", "headers": [], "cookies": [], "content": { "mimeType" : "application/json" }, "redirectURL": "", "headersSize": 0, "bodySize": 0}',
    headers = {
      Host = "mockbin.org",
      ["Content-Type"] = "application/json"
    }
  }))

  local body = assert.res_status(201, res)
  return body:sub(2, body:len() - 1)
end

local mock_bin_http = create_mock_bin()
local mock_bin_https = create_mock_bin()

describe("Plugin: http-log (log)", function()
  local client
  setup(function()
    assert(helpers.start_kong())

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "http_logging.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "http-log",
      config = {
        http_endpoint = "http://mockbin.org/bin/"..mock_bin_http
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "https_logging.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "http-log",
      config = {
        http_endpoint = "https://mockbin.org/bin/"..mock_bin_https
      }
    })
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  it("logs to HTTP", function()
    local res = assert(client:send({
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
        method = "GET",
        path = "/bin/"..mock_bin_http.."/log",
        headers = {
          Host = "mockbin.org",
          Accept = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      if #body.log.entries == 1 then
        local log_message = cjson.decode(body.log.entries[1].request.postData.text)
        assert.same("127.0.0.1", log_message.client_ip)
        return true
      end
    end)
  end, 10)

  it("logs to HTTPS", function()
    local res = assert(client:send({
      method = "GET",
      path = "/status/200",
      headers = {
        ["Host"] = "https_logging.com"
      }
    }))
    assert.res_status(200, res)

    helpers.wait_until(function()
      local client = assert(helpers.http_client(mockbin_ip, 80))
      local res = assert(client:send {
        method = "GET",
        path = "/bin/"..mock_bin_https.."/log",
        headers = {
          Host = "mockbin.org",
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
end)
