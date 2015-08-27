local ssl = require "ssl"
local url = require "socket.url"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local socket = require "socket"
local constants = require "kong.constants"
local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL
local PROXY_URL = spec_helper.PROXY_URL

-- Parses an SSL certificate returned by LuaSec
local function parse_cert(cert)
  local result = {}
  for _, v in ipairs(cert:issuer()) do
    result[v.name] = v.value
  end
  return result
end

describe("Resolver", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "tests host resolver 1", public_dns = "mockbin.com", target_url = "http://mockbin.com"},
        {name = "tests host resolver 2", public_dns = "mockbin-auth.com", target_url = "http://mockbin.com"},
        {name = "tests path resolver", target_url = "http://mockbin.com", path = "/status"},
        {name = "tests stripped path resolver", target_url = "http://mockbin.com", path = "/mockbin", strip_path = true},
        {name = "tests stripped path resolver with pattern characters", target_url = "http://mockbin.com", path = "/mockbin-with-pattern/", strip_path = true},
        {name = "tests deep path resolver", target_url = "http://mockbin.com", path = "/deep/path/", strip_path = true},
        {name = "tests dup path resolver", target_url = "http://mockbin.com", path = "/har", strip_path = true},
        {name = "tests wildcard subdomain", target_url = "http://mockbin.com/status/200", public_dns = "*.wildcard.com"},
        {name = "tests wildcard subdomain 2", target_url = "http://mockbin.com/status/201", public_dns = "wildcard.*"},
        {name = "tests preserve host", public_dns = "httpbin-nopreserve.com", target_url = "http://httpbin.org"},
        {name = "tests preserve host 2", public_dns = "httpbin-preserve.com", target_url = "http://httpbin.org", preserve_host = true}
      },
      plugin_configuration = {
        {name = "key-auth", value = {key_names = {"apikey"} }, __api = 2}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Inexistent API", function()

    it("should return Not Found when the API is not in Kong", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, nil, {host = "foo.com"})
      assert.equal(404, status)
      assert.equal('{"public_dns":["foo.com"],"message":"API not found with these values","path":"\\/request"}\n', response)
    end)

  end)

  describe("SSL", function()

    it("should work when calling SSL port", function()
      local response, status = http_client.get(STUB_GET_SSL_URL, nil, {host = "mockbin.com"})
      assert.equal(200, status)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.same("GET", parsed_response.method)
    end)

    it("should work when manually triggering the handshake on default route", function()
      local parsed_url = url.parse(STUB_GET_SSL_URL)

      local conn = socket.tcp()
      local ok, err = conn:connect(parsed_url.host, parsed_url.port)
      assert.truthy(ok)
      assert.falsy(err)

      local params = {
        mode = "client",
        verify = "none",
        options = "all",
        protocol = "tlsv1"
      }

      -- TLS/SSL initialization
      conn = ssl.wrap(conn, params)
      local ok, err = conn:dohandshake()
      assert.falsy(err)
      assert.truthy(ok)

      local cert = parse_cert(conn:getpeercertificate())

      assert.same(6, utils.table_size(cert))
      assert.same("Kong", cert.organizationName)
      assert.same("IT Department", cert.organizationalUnitName)
      assert.same("US", cert.countryName)
      assert.same("California", cert.stateOrProvinceName)
      assert.same("San Francisco", cert.localityName)
      assert.same("localhost", cert.commonName)

      conn:close()
    end)

  end)

  describe("Existing API", function()
    describe("By Host", function()
      it("should proxy when the API is in Kong", function()
        local _, status = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com"})
        assert.equal(200, status)
      end)

      it("should proxy when the Host header is not trimmed", function()
        local _, status = http_client.get(STUB_GET_URL, nil, {host = "   mockbin.com  "})
        assert.equal(200, status)
      end)

      it("should proxy when the request has no Host header but the X-Host-Override header", function()
        local _, status = http_client.get(STUB_GET_URL, nil, {["X-Host-Override"] = "mockbin.com"})
        assert.equal(200, status)
      end)

      it("should proxy when the Host header contains a port", function()
        local _, status = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com:80"})
        assert.equal(200, status)
      end)

      describe("with wildcard subdomain", function()

        it("should proxy when the public_dns is a wildcard subdomain", function()
          local _, status = http_client.get(STUB_GET_URL, nil, {host = "subdomain.wildcard.com"})
          assert.equal(200, status)

          _, status = http_client.get(STUB_GET_URL, nil, {host = "wildcard.org"})
          assert.equal(201, status)
        end)
      end)
    end)

    describe("By Path", function()
      it("should proxy when no Host is present but the request_uri matches the API's path", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/200")
        assert.equal(200, status)

        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/301")
        assert.equal(301, status)

        local _, status = http_client.get(spec_helper.PROXY_URL.."/mockbin")
        assert.equal(200, status)
      end)
      it("should not proxy when the path does not match the start of the request_uri", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/somepath/status/200")
        local body = cjson.decode(response)
        assert.equal("API not found with these values", body.message)
        assert.equal("/somepath/status/200", body.path)
        assert.equal(404, status)
      end)
      it("should proxy and strip the path if `strip_path` is true", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin/request")
        assert.equal(200, status)
        local body = cjson.decode(response)
        assert.equal("http://mockbin.com/request", body.url)
      end)
      it("should proxy and strip the path if `strip_path` is true if path has pattern characters", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin-with-pattern/request")
        assert.equal(200, status)
        local body = cjson.decode(response)
        assert.equal("http://mockbin.com/request", body.url)
      end)
      it("should proxy when the path has a deep level", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/deep/path/status/200")
        assert.equal(200, status)
      end)
      it("should not care about querystring parameters", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/mockbin?foo=bar")
        assert.equal(200, status)
      end)
      it("should not strip if the `path` pattern is repeated in the request_uri", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/har/har/of/request")
        assert.equal(200, status)
        local body = cjson.decode(response)
        local upstream_url = body.log.entries[1].request.url
        assert.equal("http://mockbin.com/har/of/request", upstream_url)
      end)
    end)

    it("should return the correct Server and Via headers when the request was proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mockbin.com"})
      assert.equal(200, status)
      assert.equal("cloudflare-nginx", headers.server)
      assert.equal(constants.NAME.."/"..constants.VERSION, headers.via)
    end)
    it("should return the correct Server and no Via header when the request was NOT proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mockbin-auth.com"})
      assert.equal(401, status)
      assert.equal(constants.NAME.."/"..constants.VERSION, headers.server)
      assert.falsy(headers.via)
    end)
  end)

  describe("Preseve Host", function()
    it("should not preserve the host (default behavior)", function()
      local response, status = http_client.get(PROXY_URL.."/get", nil, { host = "httpbin-nopreserve.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("httpbin.org", parsed_response.headers["Host"])
    end)

    it("should preserve the host (default behavior)", function()
      local response, status = http_client.get(PROXY_URL.."/get", nil, { host = "httpbin-preserve.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("httpbin-preserve.com", parsed_response.headers["Host"])
    end)
  end)
end)
