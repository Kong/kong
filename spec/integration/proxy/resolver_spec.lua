local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local constants = require "kong.constants"
local cjson = require "cjson"
local socket = require "socket"
local url = require "socket.url"
local stringy = require "stringy"
local ssl = require "ssl"
local utils = require "kong.tools.utils"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL

describe("Resolver", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests host resolver 1", public_dns = "mocbkin.com", target_url = "http://mockbin.com" },
        { name = "tests host resolver 2", public_dns = "mocbkin-auth.com", target_url = "http://mockbin.com" }
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
      local body = cjson.decode(response)
      assert.are.equal(404, status)
      assert.are.equal('API not found with Host: foo.com', body.message)
    end)

  end)

  describe("SSL", function() 

    it("should work when calling SSL port", function()
      local response, status = http_client.get(STUB_GET_SSL_URL, nil, { host = "mocbkin.com" })
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
        protocol = "tlsv1",
        verify = "none",
        options = "all",
      }

      -- TLS/SSL initialization
      conn = ssl.wrap(conn, params)
      local ok, err = conn:dohandshake()
      assert.truthy(ok)
      assert.falsy(err)

      local cert = spec_helper.parse_cert(conn:getpeercertificate())
      
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

    it("should return Success when the API is in Kong", function()
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "mocbkin.com"})
      assert.are.equal(200, status)
    end)

    it("should return Success when the Host header is not trimmed", function()
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "   mocbkin.com  "})
      assert.are.equal(200, status)
    end)

    it("should return the correct Server and Via headers when the request was proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mocbkin.com"})
      assert.are.equal(200, status)
      assert.are.equal("cloudflare-nginx", headers.server)
      assert.are.equal(constants.NAME.."/"..constants.VERSION, headers.via)
    end)

    it("should return the correct Server and no Via header when the request was NOT proxied", function()
      local _, status, headers = http_client.get(STUB_GET_URL, nil, { host = "mocbkin-auth.com"})
      assert.are.equal(403, status)
      assert.are.equal(constants.NAME.."/"..constants.VERSION, headers.server)
      assert.falsy(headers.via)
    end)

    it("should return Success when the API is in Kong and one Host headers is being sent via plain TCP", function()
      local parsed_url = url.parse(STUB_GET_URL)
      local host = parsed_url.host
      local port = parsed_url.port

      local tcp = socket.tcp()
      tcp:connect(host, port)
      tcp:send("GET "..parsed_url.path.." HTTP/1.0\r\nHost: mocbkin.com\r\n\r\n");
      local response = ""
      while true do
        local s, status, partial = tcp:receive()
        response = response..(s or partial)
        if status == "closed" then break end
      end
      tcp:close()

      assert.truthy(stringy.startswith(response, "HTTP/1.1 200 OK"))
    end)

    it("should return Success when the API is in Kong and multiple Host headers are being sent via plain TCP", function()
      local parsed_url = url.parse(STUB_GET_URL)
      local host = parsed_url.host
      local port = parsed_url.port

      local tcp = socket.tcp()
      tcp:connect(host, port)
      tcp:send("GET "..parsed_url.path.." HTTP/1.0\r\nHost: fake.com\r\nHost: mocbkin.com\r\n\r\n");
      local response = ""
      while true do
        local s, status, partial = tcp:receive()
        response = response..(s or partial)
        if status == "closed" then break end
      end
      tcp:close()

      assert.truthy(stringy.startswith(response, "HTTP/1.1 200 OK"))
    end)

  end)

end)
