local ssl_fixtures = require "spec.03-plugins.ssl.fixtures"
local helpers = require "spec.helpers"
local pl_stringx = require "pl.stringx"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local url = require "socket.url"

describe("Plugin: ssl", function()
  local client, client_ssl, api3
  setup(function()
    helpers.kill_all()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "ssl1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api1.id,
      config = {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "ssl2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api2.id,
      config = {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key,
        only_https = true
      }
    })

    api3 = assert(helpers.dao.apis:insert {
      request_host = "ssl3.com",
      upstream_url = "http://mockbin.com"
    })

    local api4 = assert(helpers.dao.apis:insert {
      request_host = "ssl4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "ssl",
      api_id = api4.id,
      config = {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key,
        only_https = true,
        accept_http_if_already_terminated = true
      }
    })

    assert(helpers.start_kong())

    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    client_ssl = assert(helpers.http_client("127.0.0.1", pl_stringx.split(helpers.test_conf.proxy_listen_ssl, ":")[2]))
    client_ssl:ssl_handshake()
  end)
  teardown(function()
    if client then
      client:close()
    end
    if client_ssl then
      client_ssl:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  describe("SSL Resolution", function()
    it("returns default CERTIFICATE when requesting other APIs", function()
      local parsed_url = url.parse("https://"..helpers.test_conf.proxy_listen_ssl)
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername test.com")
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)
    it("works when requesting a specific API", function()
      local parsed_url = url.parse("https://"..helpers.test_conf.proxy_listen_ssl)
      local _, _, stdout = pl_utils.executeex("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")
      assert.is_string(stdout:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)
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
      assert.are.same({"keep-alive", "Upgrade"}, res.headers.connection)
      assert.are.same("TLS/1.0, HTTP/1.1", res.headers.upgrade)
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

  it("works with curl", function()
    local ssl_cert_path = pl_path.join(helpers.test_conf.prefix, "ssl", "kong-default.crt")
    local ssl_key_path = pl_path.join(helpers.test_conf.prefix, "ssl", "kong-default.key")

    local _, _, stdout = pl_utils.executeex("curl -s -o /dev/null -w \"%{http_code}\" http://"..helpers.test_conf.admin_listen.."/apis/"..api3.id.."/plugins/ --form \"name=ssl\" --form \"config.cert=@"..ssl_cert_path.."\" --form \"config.key=@"..ssl_key_path.."\"")
    assert.are.equal(201, tonumber(stdout))
  end)
end)
