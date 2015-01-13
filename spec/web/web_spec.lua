local utils = require "apenode.tools.utils"
local cjson = require "cjson"
local kWebURL = "http://localhost:8001/"

local ENDPOINTS = {
  apis = {
    total = 6,
    error_message = '{"public_dns":"public_dns is required","name":"name is required","target_url":"target_url is required"}'
  },
  accounts = {
    total = 1,
    error_message = nil
  },
  applications = {
    total = 3,
    error_message = '{"account_id":"account_id is required","secret_key":"secret_key is required"}'
  },
  plugins = {
    total = 7,
    error_message = '{"name":"name is required","api_id":"api_id is required","value":"value is required"}'
  }
}

describe("Web API #web", function()

  describe("/", function()
    it("should return the apenode version and a welcome message", function()
      local response, status, headers = utils.get(kWebURL)
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.truthy(body.version)
      assert.truthy(body.tagline)
    end)
  end)

  for k,v in pairs(ENDPOINTS) do
    describe(k, function()
      it("get all", function()
        local response, status, headers = utils.get(kWebURL .. "/" .. k .. "/")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body.data)
        assert.truthy(body.total)
        assert.are.equal(v.total, body.total)
        assert.are.equal(v.total, table.getn(body.data))
      end)
      it("get one", function()
        local response, status, headers = utils.get(kWebURL .. "/" .. k .. "/1")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal("1", body.id)
      end)
      it("create with invalid params", function()
        local response, status, headers = utils.post(kWebURL .. "/" .. k .. "/", {})
        local body = cjson.decode(response)
        if v.error_message then
          assert.are.equal(400, status)
          assert.are.equal(v.error_message, response)
        else
          assert.are.equal(201, status)
          assert.truthy(body)
          assert.are.equal(2, body.id)
        end
      end)
      it("delete", function()
        local response, status, headers = utils.delete(kWebURL .. "/" .. k .. "/1")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal("1", body.id)
      end)
    end)
  end

end)
