local spec_helper = require "spec.spec_helpers"
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
        { request_host = "ssl1.com", upstream_url = "http://mockbin.com" },
        { request_host = "ssl2.com", upstream_url = "http://mockbin.com" },
        { request_host = "ssl3.com", upstream_url = "http://mockbin.com" },
        { request_host = "ssl4.com", upstream_url = "http://mockbin.com" },
      }
    }

    spec_helper.start_kong()

    -- The SSL plugin needs to be added manually because we are requiring ngx.ssl
    local _, status = http_client.post_multipart(API_URL.."/apis/ssl1.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = ssl_fixtures.cert, 
      ["config.key"] = ssl_fixtures.key})
    assert.equals(201, status)

    local _, status = http_client.post_multipart(API_URL.."/apis/ssl2.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = ssl_fixtures.cert, 
      ["config.key"] = ssl_fixtures.key,
      ["config.only_https"] = true})
    assert.equals(201, status)

    local _, status = http_client.post_multipart(API_URL.."/apis/ssl4.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = ssl_fixtures.cert, 
      ["config.key"] = ssl_fixtures.key,
      ["config.only_https"] = true,
      ["config.accept_http_if_already_terminated"] = true})
    assert.equals(201, status)
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("SSL conversions", function()
    it("should not convert an invalid cert to DER", function()
      local res, status = http_client.post_multipart(API_URL.."/apis/ssl1.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = "asd", 
      ["config.key"] = ssl_fixtures.key})
      assert.equals(400, status)
      assert.equals("Invalid SSL certificate", cjson.decode(res)["config.cert"])
    end)
    it("should not convert an invalid key to DER", function()
      local res, status = http_client.post_multipart(API_URL.."/apis/ssl1.com/plugins/", { 
      name = "ssl", 
      ["config.cert"] = ssl_fixtures.cert, 
      ["config.key"] = "hello"})
      assert.equals(400, status)
      assert.equals("Invalid SSL certificate key", cjson.decode(res)["config.key"])
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
