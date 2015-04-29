local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local constants = require "kong.constants"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("Resolver", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Inexistent API", function()

    it("should return Not Found when the API is not in Kong", function()
      local response, status, headers = http_client.get(spec_helper.STUB_GET_URL, nil, { host = "foo.com" })
      local body = cjson.decode(response)
      assert.are.equal(404, status)
      assert.are.equal('API not found with Host: "foo.com"', body.message)
    end)

  end)

  describe("Existing API", function()

    it("should return Success when the API is in Kong", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "test4.com"})
      assert.are.equal(200, status)
    end)

    it("should return Success when the Host header is not trimmed", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "   test4.com  "})
      assert.are.equal(200, status)
    end)

    it("should return the correct Server header", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "test4.com"})
      assert.are.equal("cloudflare-nginx", headers.server)
    end)

    it("should return the correct Via header", function()
      local response, status, headers = http_client.get(STUB_GET_URL, nil, { host = "test4.com"})
      assert.are.equal(constants.NAME.."/"..constants.VERSION, headers.via)
    end)

  end)
end)
