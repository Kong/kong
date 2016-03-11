local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("key-auth credentials API", function()
  local BASE_URL, credential, consumer

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/:consumer/key-auth/", function()

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {{ username = "bob" }, { username = "bob2" }}
      }
      consumer = fixtures.consumer[1]
      BASE_URL = spec_helper.API_URL.."/consumers/bob/key-auth/"
    end)

    describe("POST", function()

      it("[SUCCESS] should create a key-auth credential", function()
        local response, status = http_client.post(BASE_URL, { key = "1234" })
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
        assert.equal("1234", credential.key)

        spec_helper.get_env().dao_factory.keyauth_credentials:delete({id = credential.id})
      end)

      it("[SUCCESS] should create a key-auth credential auto-generating the key", function()
        local response, status = http_client.post(BASE_URL, {})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.truthy(credential.key)
      end)

    end)

    describe("PUT", function()

      it("[SUCCESS] should create and update", function()
        local response, status = http_client.put(BASE_URL, { key = "1234" })
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
        assert.equal("1234", credential.key)
      end)

      it("[SUCCESS] should create a key-auth credential auto-generating the key", function()
        local response, status = http_client.put(BASE_URL, {})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.truthy(credential.key)
      end)

    end)

    describe("GET", function()

      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equal(3, #(body.data))
      end)

    end)
  end)

  describe("/consumers/:consumer/key-auth/:id", function()

    describe("GET", function()

      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..credential.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(credential.id, body.id)
      end)
      it("should retrieve by id and match the consumer id", function()
        local _, status = http_client.get(spec_helper.API_URL.."/consumers/bob/key-auth/"..credential.id)
        assert.equal(200, status)
        local _, status = http_client.get(spec_helper.API_URL.."/consumers/bob2/key-auth/"..credential.id)
        assert.equal(404, status)
      end)

    end)

    describe("PATCH", function()

      it("[SUCCESS] should update a credential", function()
        local response, status = http_client.patch(BASE_URL..credential.id, { key = "4321" })
        assert.equal(200, status)
        credential = json.decode(response)
        assert.equal("4321", credential.key)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.patch(BASE_URL..credential.id, { key = "" })
        assert.equal(400, status)
        assert.equal('{"key":"key is not a string"}\n', response)
      end)

    end)

    describe("DELETE", function()

      it("[FAILURE] should return proper errors", function()
        local _, status = http_client.delete(BASE_URL.."blah")
        assert.equal(400, status)

        _, status = http_client.delete(BASE_URL.."00000000-0000-0000-0000-000000000000")
        assert.equal(404, status)
      end)

      it("[SUCCESS] should delete a credential", function()
        local _, status = http_client.delete(BASE_URL..credential.id)
        assert.equal(204, status)
      end)

    end)
  end)
end)
