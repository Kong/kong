local spec_helper = require "spec.spec_helpers"
local ssl_util = require "kong.plugins.ssl.ssl_util"
local url = require "socket.url"
local IO = require "kong.tools.io"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local ssl_fixtures = require "spec.plugins.ssl.fixtures"

local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL
local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("SSL Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "ssl-test", request_host = "ssl1.com", upstream_url = "http://mockbin.com" },
        { name = "ssl-test2", request_host = "ssl2.com", upstream_url = "http://mockbin.com" },
        { name = "ssl-test3", request_host = "ssl3.com", upstream_url = "http://mockbin.com" },
        { name = "ssl-test4", request_host = "ssl4.com", upstream_url = "http://mockbin.com" },
      },
      plugin = {
        { name = "ssl", config = { cert = ssl_fixtures.cert, key = ssl_fixtures.key }, __api = 1 },
        { name = "ssl", config = { cert = ssl_fixtures.cert, key = ssl_fixtures.key, only_https = true }, __api = 2 },
        { name = "ssl", config = { cert = ssl_fixtures.cert, key = ssl_fixtures.key, only_https = true, accept_http_if_already_terminated = true }, __api = 4 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("SSL Util", function()

    it("should not convert an invalid cert to DER", function()
      assert.falsy(ssl_util.cert_to_der("asd"))
    end)

     it("should convert a valid cert to DER", function()
      assert.truthy(ssl_util.cert_to_der(ssl_fixtures.cert))
    end)

    it("should not convert an invalid key to DER", function()
      assert.falsy(ssl_util.key_to_der("asd"))
    end)

    it("should convert a valid key to DER", function()
      assert.truthy(ssl_util.key_to_der(ssl_fixtures.key))
    end)

  end)

  describe("SSL Resolution", function()

    it("should return default CERTIFICATE when requesting other APIs", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername test4.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT Department/CN=localhost"))
    end)

    it("should work when requesting a specific API", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)
      local res = IO.os_execute("(echo \"GET /\"; sleep 2) | openssl s_client -connect "..parsed_url.host..":"..tostring(parsed_url.port).." -servername ssl1.com")

      assert.truthy(res:match("US/ST=California/L=San Francisco/O=Kong/OU=IT/CN=ssl1.com"))
    end)

  end)

  describe("only_https", function()

    it("should block request without https", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "ssl2.com" })
      assert.are.equal(426, status)
      assert.are.same("close, Upgrade", headers.connection)
      assert.are.same("TLS/1.0, HTTP/1.1", headers.upgrade)
      assert.are.same("Please use HTTPS protocol", cjson.decode(response).message)
    end)

    it("should not block request with https", function()
      local _, status = http_client.get(STUB_GET_SSL_URL, nil, { host = "ssl2.com" })
      assert.are.equal(200, status)
    end)

    it("should block request with https in x-forwarded-proto but no accept_if_already_terminated", function()
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "ssl2.com", ["x-forwarded-proto"] = "https" })
      assert.are.equal(426, status)
    end)

    it("should not block request with https", function()
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "ssl4.com", ["x-forwarded-proto"] = "https" })
      assert.are.equal(200, status)
    end)

    it("should not block request with https in x-forwarded-proto but accept_if_already_terminated", function()
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "ssl4.com", ["x-forwarded-proto"] = "https" })
      assert.are.equal(200, status)
    end)

  end)

  describe("should work with curl", function()
    local response = http_client.get(API_URL.."/apis/", {request_host="ssl3.com"})
    local api_id = cjson.decode(response).data[1].id

    local kong_working_dir = spec_helper.get_env(spec_helper.TEST_CONF_FILE).configuration.nginx_working_dir

    local ssl_cert_path = IO.path:join(kong_working_dir, "ssl", "kong-default.crt")
    local ssl_key_path = IO.path:join(kong_working_dir, "ssl", "kong-default.key")

    local res = IO.os_execute("curl -s -o /dev/null -w \"%{http_code}\" "..API_URL.."/apis/"..api_id.."/plugins/ --form \"name=ssl\" --form \"config.cert=@"..ssl_cert_path.."\" --form \"config.key=@"..ssl_key_path.."\"")
    assert.are.equal(201, tonumber(res))
  end)

end)
