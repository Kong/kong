local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local IO = require "kong.tools.io"

local CREATED_IDS = {}
local ENDPOINTS = {
  {
    collection = "apis",
    entity = {
      form = {
        public_dns = "api.mockbin.com",
        name = "mockbin",
        target_url = "http://mockbin.com"
      }
    },
    update_fields = { public_dns = "newapi.mockbin.com" },
    error_message = '{"public_dns":"At least a \'public_dns\' or a \'path\' must be specified","path":"At least a \'public_dns\' or a \'path\' must be specified","target_url":"target_url is required"}\n'
  },
  {
    collection = "consumers",
    entity = { form = { custom_id = "123456789" }},
    update_fields = { custom_id = "ABC_custom_ID" },
    error_message = '{"custom_id":"At least a \'custom_id\' or a \'username\' must be specified","username":"At least a \'custom_id\' or a \'username\' must be specified"}\n'
  },
  {
    collection = "plugins_configurations",
    entity = {
      form = {
        name = "ratelimiting",
        api_id = nil,
        consumer_id = nil,
        ["value.period"] = "second",
        ["value.limit"] = 10
      },
      json = {
        name = "ratelimiting",
        api_id = nil,
        consumer_id = nil,
        value = { period = "second", limit = 10 }
      }
    },
    update_fields = { enabled = false },
    error_message = '{"api_id":"api_id is required","name":"name is required"}\n'
  }
}

local function attach_ids()
  ENDPOINTS[3].entity.form.api_id = CREATED_IDS.apis
  ENDPOINTS[3].entity.json.api_id = CREATED_IDS.apis
  ENDPOINTS[3].entity.form.consumer_id = CREATED_IDS.consumers
  ENDPOINTS[3].entity.json.consumer_id = CREATED_IDS.consumers
end

local function test_for_each_endpoint(fn)
  for _, endpoint in ipairs(ENDPOINTS) do
    fn(endpoint, spec_helper.API_URL.."/"..endpoint.collection)
  end
end

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/", function()
    local constants = require "kong.constants"

    it("should return Kong's version and a welcome message", function()
      local response, status = http_client.get(spec_helper.API_URL)
      assert.are.equal(200, status)
      local body = json.decode(response)
      assert.truthy(body.version)
      assert.truthy(body.tagline)
      assert.are.same(constants.VERSION, body.version)
    end)

    it("should have a Server header", function()
      local _, status, headers = http_client.get(spec_helper.API_URL)
      assert.are.same(200, status)
      assert.are.same(string.format("%s/%s", constants.NAME, constants.VERSION), headers.server)
      assert.falsy(headers.via) -- Via is only set for proxied requests
    end)

  end)

  describe("POST", function()
    describe("application/x-www-form-urlencoded", function()
      test_for_each_endpoint(function(endpoint, base_url)

        it("should not create with an invalid application/x-www-form-urlencoded body", function()
          local response, status = http_client.post(base_url.."/", {})
          assert.are.equal(400, status)
          assert.are.equal(endpoint.error_message, response)
        end)

        it("should create an entity with an application/x-www-form-urlencoded body", function()
          -- Replace the IDs
          attach_ids()

          local response, status = http_client.post(base_url.."/", endpoint.entity.form)
          assert.are.equal(201, status)

          -- Save the ID for later use
          local body = json.decode(response)
          CREATED_IDS[endpoint.collection] = body.id
        end)

      end)
    end)

    describe("application/json", function()

      setup(function()
        spec_helper.drop_db()
        CREATED_IDS = {}
      end)

      test_for_each_endpoint(function(endpoint, base_url)

        it("should not create with invalid body", function()
          local response, status = http_client.post(base_url.."/", {}, {["content-type"] = "application/json"})
          assert.are.equal(400, status)
          assert.are.equal(endpoint.error_message, response)
        end)

        it("should respond 400 to malformed body", function()
          local response, status = http_client.post(base_url.."/", '{"hello":"world"', {["content-type"] = "application/json"})
          assert.are.equal(400, status)
          assert.are.equal('{"message":"Cannot parse JSON body"}\n', response)
        end)

        it("should create an entity with a valid body", function()
          -- Replace the IDs
          attach_ids()

          local json_entity = endpoint.entity.json and endpoint.entity.json or endpoint.entity.form

          local response, status = http_client.post(base_url.."/", json_entity,
            { ["content-type"] = "application/json" }
          )
          assert.are.equal(201, status)

          -- Save the ID for later use
          local body = json.decode(response)
          CREATED_IDS[endpoint.collection] = body.id
        end)

      end)
    end)

    describe("multipart/form-data", function()

      setup(function()
        spec_helper.drop_db()
        CREATED_IDS = {}
      end)

      test_for_each_endpoint(function(endpoint, base_url)

        it("should not create with invalid body", function()
          local response, status = http_client.post_multipart(base_url.."/", {})
          assert.are.equal(400, status)
          assert.are.equal(endpoint.error_message, response)
        end)

        it("should create an entity with a valid body with curl multipart", function()
          -- Replace the IDs
          attach_ids()

          local curl_str = "curl -s "..base_url.."/"
          for k, v in pairs(endpoint.entity.form) do
            local tmp = os.tmpname()
            IO.write_to_file(tmp, v)
            curl_str = curl_str.." --form \""..k.."=@"..tmp.."\""
          end

          local res = IO.os_execute(curl_str)
          local body = json.decode(res)
          assert.truthy(body)
          assert.truthy(body.id)

          http_client.delete(base_url.."/"..body.id)

          CREATED_IDS[endpoint.collection] = body.id
        end)

        it("should create an entity with a valid body", function()
          -- Replace the IDs
          attach_ids()

          local response, status = http_client.post_multipart(base_url.."/", endpoint.entity.form)
          assert.are.equal(201, status)

          -- Save the ID for later use
          local body = json.decode(response)
          CREATED_IDS[endpoint.collection] = body.id
        end)

      end)
    end)
  end)

  describe("GET all", function()
    test_for_each_endpoint(function(endpoint, base_url)

      it("should retrieve all entities", function()
        local response, status = http_client.get(base_url.."/")
        local body = json.decode(response)
        assert.are.equal(200, status)
        assert.truthy(body.data)
        assert.are.equal(1, table.getn(body.data))
      end)

    end)
  end)

  describe("GET one", function()
    test_for_each_endpoint(function(endpoint, base_url)

      it("should respond 404 to non existing entities", function()
        local response, status = http_client.get(base_url.."/00000000-0000-0000-0000-000000000000")
        assert.are.equal(404, status)
        assert.are.equal('{"message":"Not found"}\n', response)
      end)

      it("should retrieve one entity", function()
        local response, status = http_client.get(base_url.."/"..CREATED_IDS[endpoint.collection])
        local body = json.decode(response)
        assert.are.equal(200, status)
        assert.are.equal(CREATED_IDS[endpoint.collection], body.id)
      end)

    end)
  end)

  describe("PATCH", function()
    test_for_each_endpoint(function(endpoint, base_url)

      it("should respond 404 to non existing entities", function()
        local response, status = http_client.patch(base_url.."/00000000-0000-0000-0000-000000000000")
        assert.are.equal(404, status)
        assert.are.equal('{"message":"Not found"}\n', response)
      end)

      describe("application/x-www-form-urlencoded", function()

        it("should update an entity with an application/x-www-form-urlencoded body", function()
          local data = http_client.get(base_url.."/"..CREATED_IDS[endpoint.collection])
          local body = json.decode(data)

          -- Create new body
          for k, v in pairs(endpoint.update_fields) do
            body[k] = v
          end

          local response, status = http_client.patch(base_url.."/"..CREATED_IDS[endpoint.collection], body)
          assert.are.equal(200, status)
          local response_body = json.decode(response)
          assert.are.equal(CREATED_IDS[endpoint.collection], response_body.id)
          assert.are.same(body, response_body)
        end)

      end)

      describe("application/json", function()

        it("should update an entity with an application/json body", function()
          local data = http_client.get(base_url.."/"..CREATED_IDS[endpoint.collection])
          local body = json.decode(data)

          -- Create new body
          for k, v in pairs(endpoint.update_fields) do
            body[k] = v
          end

          local response, status = http_client.patch(base_url.."/"..CREATED_IDS[endpoint.collection], body,
            { ["content-type"] = "application/json" }
          )
          assert.are.equal(200, status)
          local response_body = json.decode(response)
          assert.are.equal(CREATED_IDS[endpoint.collection], response_body.id)
          assert.are.same(body, response_body)
        end)

      end)
    end)
  end)

  -- Tests on DELETE must run in that order:
  --  1. plugins_configurations
  --  2. APIs/Consumers
  -- Since deleting APIs and Consumers delete related plugins_configurations.
  describe("DELETE", function()
    test_for_each_endpoint(function(endpoint, base_url)

      it("should send 404 when trying to delete a non existing entity", function()
        local response, status = http_client.delete(base_url.."/00000000-0000-0000-0000-000000000000")
        assert.are.equal(404, status)
        assert.are.same('{"message":"Not found"}\n', response)
      end)

    end)

    it("should delete a plugin_configuration", function()
      local response, status = http_client.delete(spec_helper.API_URL.."/plugins_configurations/"..CREATED_IDS.plugins_configurations)
      assert.are.equal(204, status)
      assert.falsy(response)
    end)

    it("should delete an API", function()
      local response, status = http_client.delete(spec_helper.API_URL.."/apis/"..CREATED_IDS.apis)
      assert.are.equal(204, status)
      assert.falsy(response)
    end)

    it("should delete a Consumer", function()
      local response, status = http_client.delete(spec_helper.API_URL.."/consumers/"..CREATED_IDS.consumers)
      assert.are.equal(204, status)
      assert.falsy(response)
    end)

  end)

  describe("PUT", function()
    describe("application/x-www-form-urlencoded", function()

      setup(function()
        spec_helper.drop_db()
        CREATED_IDS = {}
      end)

      test_for_each_endpoint(function(endpoint, base_url)

        it("should not insert an entity if invalid", function()
          local response, status = http_client.put(base_url, {})
          assert.are.equal(400, status)
          assert.are.equal(endpoint.error_message, response)
        end)

        it("should insert an entity if valid", function()
          -- Replace the IDs
          attach_ids()

          local response, status = http_client.put(base_url, endpoint.entity.form)
          assert.are.equal(201, status)

          -- Save the ID for later use
          local response_body = json.decode(response)
          CREATED_IDS[endpoint.collection] = response_body.id
        end)

        it("should update the entity if a full body is given", function()
          local data = http_client.get(base_url.."/"..CREATED_IDS[endpoint.collection])
          local body = json.decode(data)

          -- Create new body
          for k, v in pairs(endpoint.update_fields) do
            body[k] = v
          end

          local response, status = http_client.put(base_url, body)
          assert.are.equal(200, status)
          local response_body = json.decode(response)
          assert.are.equal(CREATED_IDS[endpoint.collection], response_body.id)
          assert.are.same(body, response_body)
        end)

      end)
    end)

    describe("application/json", function()

      setup(function()
        spec_helper.drop_db()
        CREATED_IDS = {}
      end)

      test_for_each_endpoint(function(endpoint, base_url)

        it("should not insert an entity if invalid", function()
          local response, status = http_client.put(base_url, {}, { ["content-type"] = "application/json" })
          assert.are.equal(400, status)
          assert.are.equal(endpoint.error_message, response)
        end)

        it("should insert an entity if valid", function()
          -- Replace the IDs
          attach_ids()

          local json_entity = endpoint.entity.json and endpoint.entity.json or endpoint.entity.form

          local response, status = http_client.put(base_url, json_entity, { ["content-type"] = "application/json" })
          assert.are.equal(201, status)

          -- Save the ID for later use
          local response_body = json.decode(response)
          CREATED_IDS[endpoint.collection] = response_body.id
        end)

        it("should update the entity if a full body is given", function()
          local data, status = http_client.get(base_url.."/"..CREATED_IDS[endpoint.collection])
          assert.are.equal(200, status)
          local body = json.decode(data)

          -- Create new body
          for k, v in pairs(endpoint.update_fields) do
            body[k] = v
          end

          local response, status = http_client.put(base_url, body, { ["content-type"] = "application/json" })
          assert.are.equal(200, status)
          local response_body = json.decode(response)
          assert.are.equal(CREATED_IDS[endpoint.collection], response_body.id)
          assert.are.same(body, response_body)
        end)

      end)
    end)
  end)

end)
