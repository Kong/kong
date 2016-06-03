local spec_helper = require "spec.spec_helpers"
local ssl = require "ssl"
local url = require "socket.url"
local meta = require "kong.meta"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local socket = require "socket"
local constants = require "kong.constants"
local http_client = require "kong.tools.http_client"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL
local PROXY_URL = spec_helper.PROXY_URL
local API_URL = spec_helper.API_URL

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
        {name = "tests-host-resolver-1", request_host = "mockbin.com", upstream_url = "http://mockbin.com"},
        {name = "tests-host-resolver-2", request_host = "mockbin-auth.com", upstream_url = "http://mockbin.com"},
        {name = "tests-request_path-resolver", upstream_url = "http://mockbin.com", request_path = "/status"},
        {name = "tests-stripped-request_path-resolver", upstream_url = "http://mockbin.com", request_path = "/mockbin", strip_request_path = true},
        {name = "tests-stripped-request_path-resolver-with-pattern-characters", upstream_url = "http://mockbin.com", request_path = "/mockbin-with-pattern/", strip_request_path = true},
        {name = "tests-deep-request_path-resolver", upstream_url = "http://mockbin.com", request_path = "/deep/request_path/", strip_request_path = true},
        {name = "tests-dup-request_path-resolver", upstream_url = "http://mockbin.com", request_path = "/har", strip_request_path = true},
        {name = "tests-wildcard-subdomain", upstream_url = "http://mockbin.com/status/200", request_host = "*.wildcard.com"},
        {name = "tests-wildcard-subdomain-2", upstream_url = "http://mockbin.com/status/201", request_host = "wildcard.*"},
        {name = "tests-preserve-host", request_host = "httpbin-nopreserve.com", upstream_url = "http://httpbin.org"},
        {name = "tests-preserve-host-2", request_host = "httpbin-preserve.com", upstream_url = "http://httpbin.org", preserve_host = true},
        {name = "tests-preserve-host-3", strip_request_path = true, preserve_host = true, request_path = "/hello", upstream_url = "http://httpbin.org"},
        {name = "tests-uri", request_host = "mockbin-uri.com", upstream_url = "http://mockbin.org"},
        {name = "tests-trailing-slash-path", request_path = "/test-trailing-slash", strip_request_path = true, upstream_url = "http://www.mockbin.org/request"},
        {name = "tests-trailing-slash-path2", request_path = "/test-trailing-slash2", strip_request_path = false, upstream_url = "http://www.mockbin.org/request"},
        {name = "tests-trailing-slash-path3", request_path = "/test-trailing-slash3", strip_request_path = true, upstream_url = "http://www.mockbin.org"},
        {name = "tests-trailing-slash-path4", request_path = "/test-trailing-slash4", strip_request_path = true, upstream_url = "http://www.mockbin.org/"},
        {name = "tests-deep-path", request_path = "/hello/world", strip_request_path = true, upstream_url = "http://mockbin.com"},
        {name = "tests-deep-path-two", request_path = "/hello/world/wot", strip_request_path = true, upstream_url = "http://httpbin.org"},
        {name = "tests-request_path-resolver2", upstream_url = "http://mockbin.com", request_path = "/headers"}
      },
      plugin = {
        {name = "key-auth", config = {key_names = {"apikey"} }, __api = 2}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Inexistent API", function()
    it("should return Not Found when the API is not in Kong", function()
      local response, status, headers = http_client.get(spec_helper.STUB_GET_URL, nil, {host = "foo.com"})
      assert.equal(404, status)
      assert.equal('{"request_path":"\\/request","message":"API not found with these values","request_host":["foo.com"]}\n', response)
      assert.falsy(headers[constants.HEADERS.PROXY_LATENCY:lower()])
      assert.falsy(headers[constants.HEADERS.UPSTREAM_LATENCY:lower()])
      assert.falsy(headers[constants.HEADERS.FORWARDED_HOST:lower()])
      assert.falsy(headers[constants.HEADERS.FORWARDED_PREFIX:lower()])
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
        local response, status = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com"})
        assert.equal(200, status)

        local body = cjson.decode(response)
        assert.equal("mockbin.com", body.headers[constants.HEADERS.FORWARDED_HOST:lower()])
        assert.falsy(body.headers[constants.HEADERS.FORWARDED_PREFIX:lower()])
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
        local response, status = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com:80"})
        assert.equal(200, status)

        local body = cjson.decode(response)
        assert.equal("mockbin.com", body.headers[constants.HEADERS.FORWARDED_HOST:lower()])
        assert.falsy(body.headers[constants.HEADERS.FORWARDED_PREFIX:lower()])
      end)
      describe("with wildcard subdomain", function()
        it("should proxy when the request_host is a wildcard subdomain", function()
          local _, status = http_client.get(STUB_GET_URL, nil, {host = "subdomain.wildcard.com"})
          assert.equal(200, status)

          _, status = http_client.get(STUB_GET_URL, nil, {host = "wildcard.org"})
          assert.equal(201, status)
        end)
      end)
    end)

    describe("By request_path", function()
      it("should proxy when no Host is present but the request_uri matches the API's request_path", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/200")
        assert.equal(200, status)

        local _, status = http_client.get(spec_helper.PROXY_URL.."/status/301")
        assert.equal(301, status)

        local _, status = http_client.get(spec_helper.PROXY_URL.."/mockbin")
        assert.equal(200, status)


        local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin/request")
        assert.equal(200, status)

        local body = cjson.decode(response)
        assert.equal("/mockbin", body.headers[constants.HEADERS.FORWARDED_PREFIX:lower()])
        assert.falsy(body.headers[constants.HEADERS.FORWARDED_HOST:lower()])

        -- There should be no X-Forwarded-Prefix if no prefix is being stripped
        local response, status = http_client.get(spec_helper.PROXY_URL.."/headers")
        assert.equal(200, status)
        local body = cjson.decode(response)
        assert.falsy(body.headers[constants.HEADERS.FORWARDED_HOST:lower()])
        for _, v in ipairs(body.headers) do
          if v.name == constants.HEADERS.FORWARDED_PREFIX:lower() then
            error(constants.HEADERS.FORWARDED_PREFIX.." should not be set")
          end
        end        
      end)
      it("should not proxy when the request_path does not match the start of the request_uri", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/somerequest_path/status/200")
        local body = cjson.decode(response)
        assert.equal("API not found with these values", body.message)
        assert.equal("/somerequest_path/status/200", body.request_path)
        assert.equal(404, status)
      end)
      it("should proxy when the request_path has a deep level", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/deep/request_path/status/200")
        assert.equal(200, status)

        local response, status = http_client.get(spec_helper.PROXY_URL.."/deep/request_path/request")
        assert.equal(200, status)

        local body = cjson.decode(response)
        assert.equal("/deep/request_path", body.headers[constants.HEADERS.FORWARDED_PREFIX:lower()])
        assert.falsy(body.headers[constants.HEADERS.FORWARDED_HOST:lower()])
      end)
      it("should not care about querystring parameters", function()
        local _, status = http_client.get(spec_helper.PROXY_URL.."/mockbin?foo=bar")
        assert.equal(200, status)
      end)
      it("should not add a trailing slash when strip_path is disabled", function()
        local response, status = http_client.get(spec_helper.PROXY_URL.."/test-trailing-slash2", {hello = "world"})
        assert.equal(200, status)
        assert.equal("http://www.mockbin.org/request/test-trailing-slash2?hello=world", cjson.decode(response).url)
      end)
      it("should properly handle deep paths", function()
        -- Should be httpbin
        local response, status = http_client.get(spec_helper.PROXY_URL.."/hello/world/wot/get")
        assert.equal(200, status)
        local body = cjson.decode(response)
        assert.truthy(body.args)
        assert.truthy(body.headers)
        
        -- Should be Mockbin
        local response, status = http_client.get(spec_helper.PROXY_URL.."/hello/world/request")
        assert.equal(200, status)
        local body = cjson.decode(response)
        assert.truthy(body.postData)
        assert.truthy(body.headers)
      end)
    end)

    it("should return the correct Server and Via headers when the request was proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com"})
      assert.equal(200, status)
      assert.equal("cloudflare-nginx", headers.server)
      assert.equal(meta._NAME.."/"..meta._VERSION, headers.via)
    end)
    it("should return the correct Server and no Via header when the request was NOT proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, {host = "mockbin-auth.com"})
      assert.equal(401, status)
      assert.equal(meta._NAME.."/"..meta._VERSION, headers.server)
      assert.falsy(headers.via)
    end)
    it("should return correct timing headers when the request was proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, {host = "mockbin.com"})
      assert.equal(200, status)
      assert.truthy(headers[constants.HEADERS.PROXY_LATENCY:lower()])
      assert.truthy(headers[constants.HEADERS.UPSTREAM_LATENCY:lower()])
    end)
  end)

  describe("preserve_host", function()
    it("should not preserve the host (default behavior)", function()
      local response, status = http_client.get(PROXY_URL.."/get", nil, {host = "httpbin-nopreserve.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("httpbin.org", parsed_response.headers["Host"])
    end)

    it("should preserve the host (default behavior)", function()
      local response, status = http_client.get(PROXY_URL.."/get", nil, {host = "httpbin-preserve.com"})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("httpbin-preserve.com", parsed_response.headers["Host"])
    end)

    it("should preserve the host with a request path", function()
      local response, status = http_client.get(PROXY_URL.."/hello/get")
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("localhost", parsed_response.headers["Host"])
    end)
  end)

  describe("strip_path", function()
    it("should strip the request_path if `strip_request_path` is true", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin/request")
      assert.equal(200, status)
      local body = cjson.decode(response)
      assert.equal("http://mockbin.com/request", body.url)
    end)
    it("should strip the request_path if `strip_request_path` is true if `request_path` has pattern characters", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/mockbin-with-pattern/request")
      assert.equal(200, status)
      local body = cjson.decode(response)
      assert.equal("http://mockbin.com/request", body.url)
    end)
    it("should not strip if the `request_path` pattern is repeated in the request_uri", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/har/har/of/request")
      assert.equal(200, status)
      local body = cjson.decode(response)
      local upstream_url = body.log.entries[1].request.url
      assert.equal("http://mockbin.com/har/of/request", upstream_url)
    end)
    it("should not add a trailing slash when strip_path is enabled", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/test-trailing-slash", {hello = "world"})
      assert.equal(200, status)
      assert.equal("http://www.mockbin.org/request?hello=world", cjson.decode(response).url)
    end)
    it("should not add a trailing slash when strip_path is enabled and upstream_url has no path", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/test-trailing-slash3/request", {hello = "world"})
      assert.equal(200, status)
      assert.equal("http://www.mockbin.org/request?hello=world", cjson.decode(response).url)
    end)
    it("should not add a trailing slash when strip_path is enabled and upstream_url has single path", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/test-trailing-slash4/request", {hello = "world"})
      assert.equal(200, status)
      assert.equal("http://www.mockbin.org/request?hello=world", cjson.decode(response).url)
    end)
    it("should add a trailing slash when strip_path is enabled and the request has a final slash", function()
      local response, status = http_client.get(spec_helper.PROXY_URL.."/test-trailing-slash/", {hello = "world"})
      assert.equal(200, status)
      assert.equal("http://www.mockbin.org/request/?hello=world", cjson.decode(response).url)
    end)
  end)

  describe("Percent-encoding", function()
    it("should leave percent-encoded values in URI untouched", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL.."/hello%2Fworld", {}, {host = "mockbin-uri.com"})
      assert.equal(200, status)
      assert.equal("http://mockbin-uri.com/request/hello%2fworld", cjson.decode(response).url)
    end)
    it("should leave untouched percent-encoded values in querystring", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, {foo = "abc%7Cdef%2c%20world"}, {host = "mockbin-uri.com"})
      assert.equal(200, status)
      assert.equal("http://mockbin-uri.com/request?foo=abc%7cdef%2c%20world", cjson.decode(response).url)
    end)
    it("should leave untouched percent-encoded keys in querystring", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, {["hello%20world"] = "foo"}, {host = "mockbin-uri.com"})
      assert.equal(200, status)
      assert.equal("http://mockbin-uri.com/request?hello%20world=foo", cjson.decode(response).url)
    end)
    it("should percent-encoded keys in querystring", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, {["hello world"] = "foo"}, {host = "mockbin-uri.com"})
      assert.equal(200, status)
      assert.equal("http://mockbin-uri.com/request?hello%20world=foo", cjson.decode(response).url)
    end)
    it("should percent-encoded keys in querystring", function()
      local response, status = http_client.get(spec_helper.STUB_GET_URL, {foo = "abc|def, world"}, {host = "mockbin-uri.com"})
      assert.equal(200, status)
      assert.equal("http://mockbin-uri.com/request?foo=abc%7cdef%2c%20world", cjson.decode(response).url)
    end)
  end)

  describe("Priority in request_path resolutions", function()
    setup(function()
      spec_helper.insert_fixtures {
        api = {
          {name = "tests-root-path", upstream_url = "http://httpbin.org", request_path = "/"},
          {name = "tests-root-path2", upstream_url = "http://mockbin.com", request_path = "/noroot", strip_request_path = true}
        }
      }

      spec_helper.restart_kong()
    end)

    teardown(function()
      local _, status = http_client.delete(API_URL.."/apis/tests-root-path")
      assert.equal(204, status)
      local _, status = http_client.delete(API_URL.."/apis/tests-root-path2")
      assert.equal(204, status)
    end)

    it("should work for root request_path", function()
      local response, status = http_client.get(PROXY_URL.."/get", {})
      assert.equal(200, status)
      assert.equal("http://httpbin.org/get", cjson.decode(response).url)
    end)
    it("should work for non root request_path", function()
      local response, status = http_client.get(PROXY_URL.."/noroot/request", {})
      assert.equal(200, status)
      assert.equal("http://mockbin.com/request", cjson.decode(response).url)
    end)
  end)
end)
