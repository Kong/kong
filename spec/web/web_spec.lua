local utils = require "kong.tools.utils"
local cjson = require "cjson"
local kWebURL = "http://localhost:8001/"

local IDS = {}

local ENDPOINTS = {
  {
    collection = "apis",
    total = 7,
    entity = {
      public_dns = "api.httpbin.com",
      name = "httpbin",
      target_url = "http://httpbin.org"
    },
    error_message = '{"public_dns":"public_dns is required","name":"name is required","target_url":"target_url is required"}'
  },
  {
    collection = "accounts",
    total = 3,
    entity = {},
    error_message = nil
  },
  {
    collection = "applications",
    total = 4,
    entity = {
      public_key = "PUB_key",
      secret_key = "SEC_key",
      account_id = function()
        return IDS.accounts
      end
    },
    error_message = '{"account_id":"account_id is required","secret_key":"secret_key is required","public_key":"public_key is required"}'
  },
  {
    collection = "plugins",
    total = 8,
    entity = {
      name = "ratelimiting",
      api_id = function()
        return IDS.apis
      end,
      application_id = function()
        return IDS.applications
      end,
      value = '{"period":"second", "limit": 10}'
    },
    error_message = '{"name":"name is required","api_id":"api_id is required","value":"value is required"}'
  }
}

describe("Web API #web", function()

  describe("/", function()
    it("should return Kong's version and a welcome message", function()
      local response, status, headers = utils.get(kWebURL)
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.truthy(body.version)
      assert.truthy(body.tagline)
    end)
  end)

  for i,v in ipairs(ENDPOINTS) do
    describe("#"..v.collection, function()
      it("should create the entity", function()
        -- Replace the IDs
        for k,p in pairs(v.entity) do
          if type(p) == "function" then
            v.entity[k] = p()
          end
        end

        local response, status, headers = utils.post(kWebURL.."/"..v.collection.."/", v.entity)
        local body = cjson.decode(response)
        assert.are.equal(201, status)
        assert.truthy(body)

        -- Save the ID for later use
        IDS[v.collection] = body.id
      end)
      it("should get all", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body.data)
        --assert.truthy(body.total)
        --assert.are.equal(v.total, body.total)
        assert.are.equal(v.total, table.getn(body.data))
      end)
      it("should get one", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/"..IDS[v.collection])
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal(IDS[v.collection], body.id)
      end)
      it("should return not found", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/"..IDS[v.collection].."blah")
        print(response)
        local body = cjson.decode(response)
        assert.are.equal(404, status)
        assert.truthy(body)
        assert.are.equal("", response)
      end)
      it("should create with invalid params", function()
        local response, status, headers = utils.post(kWebURL.."/"..v.collection.."/", {})
        local body = cjson.decode(response)
        if v.error_message then
          assert.are.equal(400, status)
          assert.are.equal(v.error_message, response)
        else
          assert.are.equal(201, status)
          assert.truthy(body)
          assert.are.equal(IDS[v.collection], body.id)
        end
      end)
    end)
  end

  for i,v in ipairs(ENDPOINTS) do
    describe("#"..v.collection, function()
      it("should delete one", function()
        local response, status, headers = utils.delete(kWebURL.."/"..v.collection.."/"..IDS[v.collection])
        assert.are.equal(204, status)
      end)
    end)
  end

end)
