local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local created_ids = {}

local kWebURL = "http://localhost:8001/"
local ENDPOINTS = {
  {
    collection = "apis",
    total = 7,
    entity = {
      public_dns = "api.httpbin.com",
      name = "httpbin",
      target_url = "http://httpbin.org"
    },
    update_fields = {
      public_dns = "newapi.httpbin.com"
    },
    error_message = '{"public_dns":"public_dns is required","name":"name is required","target_url":"target_url is required"}'
  },
  {
    collection = "accounts",
    total = 3,
    entity = {
      provider_id = "123456789"
    },
    update_fields = {
      provider_id = "ABC_provider_ID"
    },
    error_message = nil
  },
  {
    collection = "applications",
    total = 4,
    entity = {
      public_key = "PUB_key",
      secret_key = "SEC_key",
      account_id = function()
        return created_ids.accounts
      end
    },
    update_fields = {
      public_key = "newPUB",
      secret_key = "newSEC"
    },
    error_message = '{"account_id":"account_id is required","public_key":"public_key is required"}'
  },
  {
    collection = "plugins",
    total = 8,
    entity = {
      name = "ratelimiting",
      api_id = function()
        return created_ids.apis
      end,
      application_id = function()
        return created_ids.applications
      end,
      value = '{"period":"second", "limit": 10}'
    },
    update_fields = {
      enabled = false
    },
    error_message = '{"name":"name is required","api_id":"api_id is required","value":"value is required"}'
  }
}

describe("Web API #web", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

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

      it("should not create on POST with invalid parameters", function()
        if v.collection ~= "accounts" then
          local response, status, headers = utils.post(kWebURL.."/"..v.collection.."/", {})
          assert.are.equal(400, status)
          assert.are.equal(v.error_message, response)
        end
      end)

      it("should create an entity from valid paremeters", function()
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
        created_ids[v.collection] = body.id
      end)

      it("should GET all entities", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body.data)
        --assert.truthy(body.total)
        --assert.are.equal(v.total, body.total)
        assert.are.equal(v.total, table.getn(body.data))
      end)

      it("should GET one entity", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal(created_ids[v.collection], body.id)
      end)

      it("should return not found on GET", function()
        local response, status, headers = utils.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection].."blah")
        local body = cjson.decode(response)
        assert.are.equal(404, status)
        assert.truthy(body)
        assert.are.equal('{"id":"'..created_ids[v.collection]..'blah is an invalid uuid"}', response)
      end)

      it("should update a created entity on PUT", function()
        local data = utils.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        local body = cjson.decode(data)

        -- Create new body
        for k,v in pairs(v.update_fields) do
          body[k] = v
        end

        local response, status, headers = utils.put(kWebURL.."/"..v.collection.."/"..created_ids[v.collection], body)
        body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal(created_ids[v.collection], body.id)

        for k,v in pairs(v.update_fields) do
          assert.are.equal(v, body[k])
        end
      end)

    end)
  end

  for i,v in ipairs(ENDPOINTS) do
    describe("#"..v.collection, function()

      it("should delete an entity on DELETE", function()
        local response, status, headers = utils.delete(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        assert.are.equal(204, status)
      end)

    end)
  end

end)
