local ssl_fixtures = require "spec.03-plugins.16-ssl.fixtures"
local helpers = require "spec.helpers"

describe("Plugin: ssl (access)", function()
  local client, client_ssl

  setup(function()
    assert(helpers.start_kong())

    local api = assert(helpers.dao.apis:insert {
      request_host = "ssl2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        only_https = true,
        key = ssl_fixtures.key,
        cert = ssl_fixtures.cert
      }
    })

    api = assert(helpers.dao.apis:insert {
      request_host = "ssl4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api.id,
      config = {
        only_https = true,
        key = ssl_fixtures.key,
        cert = ssl_fixtures.cert,
        accept_http_if_already_terminated = true
      }
    })

    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    client_ssl = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_ssl_port))
    client_ssl:ssl_handshake()
  end)

  teardown(function()
    if client and client_ssl then
      client:close()
      client_ssl:close()
    end
    helpers.stop_kong()
  end)

  describe("only_https", function()
    it("blocks request without https", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          Host = "ssl2.com"
        }
      })
      local body = assert.res_status(426, res)
      assert.equal([[{"message":"Please use HTTPS protocol"}]], body)
      assert.contains("Upgrade", res.headers.connection)
      assert.equal("TLS/1.0, HTTP/1.1", res.headers.upgrade)
    end)
    it("does not block request with https", function()
      local res = assert(client_ssl:send {
        method = "GET",
        path = "/status/200",
        headers = {
          Host = "ssl2.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks request with https in x-forwarded-proto but no accept_if_already_terminated", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          Host = "ssl2.com",
          ["x-forwarded-proto"] = "https"
        }
      })
      assert.res_status(426, res)
    end)
    it("does not block request with x-forwarded-proto and accept_if_already_terminated", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          Host = "ssl4.com",
          ["x-forwarded-proto"] = "https"
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks request with invalid x-forwarded-proto but accept_if_already_terminated", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          Host = "ssl4.com",
          ["x-forwarded-proto"] = "httpsa"
        }
      })
      assert.res_status(426, res)
    end)
  end)
end)
