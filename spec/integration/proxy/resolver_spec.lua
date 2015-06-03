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
        { name = "tests host resolver 1", public_dns = "mockbin.com", target_url = "http://mockbin.com" },
        { name = "tests host resolver 2", public_dns = "mockbin-auth.com", target_url = "http://mockbin.com" },
        { name = "tests path resolver", public_dns = "mockbin-path.com", target_url = "http://mockbin.com", path = "/status/" },
        { name = "tests stripped path resolver", public_dns = "mockbin-stripped-path.com", target_url = "http://mockbin.com", path = "/mockbin/", strip_path = true }
      },
      plugin_configuration = {
        { name = "keyauth", value = {key_names = {"apikey"} }, __api = 2 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Inexistent API", function()

    it("should return Not Found when the API is not in Kong", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "foo.com" })
      assert.are.equal(404, status)
      assert.are.equal('{"public_dns":["foo.com"],"message":"API not found with these values","path":"\\/request"}\n', response)
    end)

  end)

  describe("SSL", function()

    it("should work when calling SSL port", function()
      local response, status = http_client.get(STUB_GET_SSL_URL, nil, { host = "mockbin.com" })
      assert.are.equal(200, status)
      assert.truthy(response)
      local parsed_response = cjson.decode(response)
      assert.are.same("GET", parsed_response.method)
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

      assert.are.same(6, utils.table_size(cert))
      assert.are.same("Kong", cert.organizationName)
      assert.are.same("IT", cert.organizationalUnitName)
      assert.are.same("US", cert.countryName)
      assert.are.same("California", cert.stateOrProvinceName)
      assert.are.same("San Francisco", cert.localityName)
      assert.are.same("localhost", cert.commonName)

      conn:close()
    end)

  end)

  describe("Existing API", function()
    describe("By Host", function()

      it("should proxy when the API is in Kong", function()
        local _, status = http_client.get(STUB_GET_URL, nil, { host = "mockbin.com"})
        assert.are.equal(200, status)
      end)

      it("should proxy when the Host header is not trimmed", function()
        local _, status = http_client.get(STUB_GET_URL, nil, { host = "   mockbin.com  "})
        assert.are.equal(200, status)
      end)

      it("should proxy when the request has no Host header but the X-Host-Override header", function()
        local _, status = http_client.get(STUB_GET_URL, nil, { ["X-Host-Override"] = "mockbin.com"})
        assert.are.equal(200, status)
      end)

    end)

    describe("By Path", function()

      it("should proxy when no Host is present but the request_uri matches the API's path", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/200")
        assert.are.equal(200, status)

        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/301")
        assert.are.equal(301, status)
      end)

      it("should proxy and strip the path if `strip_path` is true", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin/request")
        assert.are.equal(200, status)
        local body = cjson.decode(response)
        assert.are.equal("http://mockbin.com/request", body.url)
      end)

      it("should not proxy when the path does not the start of the request_uri", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/somepath/status/200")
        local body = cjson.decode(response)
        assert.are.equal("API not found with these values", body.message)
        assert.are.equal("/somepath/status/200", body.path)
        assert.are.equal(404, status)
      end)

    end)

    it("should return the correct Server and Via headers when the request was proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mockbin.com"})
      assert.are.equal(200, status)
      assert.are.equal("cloudflare-nginx", headers.server)
      assert.are.equal(constants.NAME.."/"..constants.VERSION, headers.via)
    end)

    it("should return the correct Server and no Via header when the request was NOT proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mockbin-auth.com"})
      assert.are.equal(403, status)
      assert.are.equal(constants.NAME.."/"..constants.VERSION, headers.server)
      assert.falsy(headers.via)
    end)

  end)
end)
