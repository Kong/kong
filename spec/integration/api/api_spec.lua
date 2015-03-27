local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local env = spec_helper.get_env()
local created_ids = {}

local kWebURL = spec_helper.API_URL
local ENDPOINTS = {
  {
    collection = "apis",
    total = table.getn(env.faker.FIXTURES.api) + 1,
    entity = {
      public_dns = "api.mockbin.com",
      name = "mockbin",
      target_url = "http://mockbin.com"
    },
    update_fields = {
      public_dns = "newapi.mockbin.com"
    },
    error_message = '{"public_dns":"public_dns is required","name":"name is required","target_url":"target_url is required"}'
  },
  {
    collection = "consumers",
    total = table.getn(env.faker.FIXTURES.consumer) + 1,
    entity = {
      custom_id = "123456789"
    },
    update_fields = {
      custom_id = "ABC_custom_ID"
    },
    error_message = nil
  },
  {
    collection = "basicauth_credentials",
    total = table.getn(env.faker.FIXTURES.basicauth_credential) + 1,
    entity = {
      username = "username5555",
      password = "password5555",
      consumer_id = function()
        return created_ids.consumers
      end
    },
    update_fields = {
      username = "upd_username5555",
      password = "upd_password5555"
    },
    error_message = '{"username":"username is required","consumer_id":"consumer_id is required"}'
  },
  {
    collection = "keyauth_credentials",
    total = table.getn(env.faker.FIXTURES.keyauth_credential) + 1,
    entity = {
      key = "apikey5555",
      consumer_id = function()
        return created_ids.consumers
      end
    },
    update_fields = {
      key = "upd_apikey5555",
    },
    error_message = '{"key":"key is required","consumer_id":"consumer_id is required"}'
  },
  {
    collection = "plugins_configurations",
    total = table.getn(env.faker.FIXTURES.plugin_configuration) + 1,
    entity = {
      name = "ratelimiting",
      api_id = function()
        return created_ids.apis
      end,
      consumer_id = function()
        return created_ids.consumers
      end,
      ["value.period"] = "second",
      ["value.limit"] = 10
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
      local response, status, headers = http_client.get(kWebURL)
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.truthy(body.version)
      assert.truthy(body.tagline)
    end)

  end)

  for i, v in ipairs(ENDPOINTS) do
    describe("#"..v.collection, function()

      it("should not create on POST with invalid parameters", function()
        if v.collection ~= "consumers" then
          local response, status, headers = http_client.post(kWebURL.."/"..v.collection.."/", {})
          assert.are.equal(400, status)
          assert.are.equal(v.error_message, response)
        end
      end)

      it("should create an entity from valid paremeters", function()
        -- Replace the IDs
        for k, p in pairs(v.entity) do
          if type(p) == "function" then
            v.entity[k] = p()
          end
        end

        local response, status, headers = http_client.post(kWebURL.."/"..v.collection.."/", v.entity)
        local body = cjson.decode(response)
        assert.are.equal(201, status)
        assert.truthy(body)

        -- Save the ID for later use
        created_ids[v.collection] = body.id
      end)

      it("should GET all entities", function()
        local response, status, headers = http_client.get(kWebURL.."/"..v.collection.."/")
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body.data)
        --assert.truthy(body.total)
        --assert.are.equal(v.total, body.total)
        assert.are.equal(v.total, table.getn(body.data))
      end)

      it("should GET one entity", function()
        local response, status, headers = http_client.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        local body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body)
        assert.are.equal(created_ids[v.collection], body.id)
      end)

      it("should return not found on GET", function()
        local response, status, headers = http_client.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection].."blah")
        local body = cjson.decode(response)
        assert.are.equal(404, status)
        assert.truthy(body)
        assert.are.equal('{"id":"'..created_ids[v.collection]..'blah is an invalid uuid"}', response)
      end)

      it("should update a created entity on PUT", function()
        local data = http_client.get(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        local body = cjson.decode(data)

        -- Create new body
        for k,v in pairs(v.update_fields) do
          body[k] = v
        end

        local response, status, headers = http_client.put(kWebURL.."/"..v.collection.."/"..created_ids[v.collection], body)
        local new_body = cjson.decode(response)
        assert.are.equal(200, status)
        assert.truthy(new_body)
        assert.are.equal(created_ids[v.collection], new_body.id)

        for k,v in pairs(v.update_fields) do
          assert.are.equal(v, new_body[k])
        end

        assert.are.same(body, new_body)
      end)

      it("should not update when the content-type is wrong", function()
        local response, status, headers = http_client.put(kWebURL.."/"..v.collection.."/"..created_ids[v.collection], body, { ["content-type"] = "application/x-www-form-urlencoded"})
        assert.are.equal(415, status)
        assert.are.equal("{\"message\":\"Unsupported Content-Type. Use \\\"application\\\/json\\\"\"}", response)
      end)

      it("should not save when the content-type is wrong", function()
        local response, status, headers = http_client.post(kWebURL.."/"..v.collection.."/", v.entity, { ["content-type"] = "application/json"})
        assert.are.equal(415, status)
        assert.are.equal("{\"message\":\"Unsupported Content-Type. Use \\\"application\\\/x-www-form-urlencoded\\\"\"}", response)
      end)

    end)
  end

  for i,v in ipairs(ENDPOINTS) do
    describe("#"..v.collection, function()

      it("should delete an entity on DELETE", function()
        local response, status, headers = http_client.delete(kWebURL.."/"..v.collection.."/"..created_ids[v.collection])
        assert.are.equal(204, status)
      end)

    end)
  end

end)
