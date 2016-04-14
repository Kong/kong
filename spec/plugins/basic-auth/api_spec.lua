local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("Basic Auth Credentials API", function()
  local BASE_URL, credential, consumer, consumer_alice

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/:consumer/basic-auth/", function()

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {{username = "bob"}, {username = "alice"}}
      }
      consumer = fixtures.consumer[1]
      consumer_alice = fixtures.consumer[2]
      BASE_URL = spec_helper.API_URL.."/consumers/bob/basic-auth/"
    end)

    describe("POST", function()

      teardown(function()
        if credential == nil then return end -- teardown gets executed even if the tag was excluded
        local dao = spec_helper.get_env().dao_factory
        local res, err = dao.basicauth_credentials:delete(credential)
        assert.is_table(res)
        assert.falsy(err)
      end)

      it("[SUCCESS] should create a basicauth credential", function()
        local response, status = http_client.post(BASE_URL, {username = "bob", password = "1234"})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
      end)

      it("[SUCCESS] should encrypt a password", function()
        local base_url = spec_helper.API_URL.."/consumers/alice/basic-auth/"
        local response, status = http_client.post(base_url, {username = "alice", password = "1234"})
        assert.equal(201, status)

        credential = json.decode(response)
        assert.equal(consumer_alice.id, credential.consumer_id)
        assert.not_equal("1234", credential.password)

        local crypto = require "kong.plugins.basic-auth.crypto"
        local hash = crypto.encrypt({consumer_id = consumer_alice.id, password = "1234"})
        assert.equal(hash, credential.password)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.post(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"username":"username is required"}\n', response)
      end)

    end)

    describe("PUT", function()

      it("[SUCCESS] should create and update", function()
        local response, status = http_client.put(BASE_URL, {username = "alice", password = "1234"})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.put(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"username":"username is required"}\n', response)
      end)

    end)

    describe("GET", function()

      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equal(2, #(body.data))
      end)

    end)
  end)

  describe("/consumers/:consumer/basic-auth/:id", function()

    describe("GET", function()
      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..credential.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(credential.id, body.id)
      end)
      it("should retrieve by id and match the consumer id", function()
        local _, status = http_client.get(spec_helper.API_URL.."/consumers/bob/basic-auth/"..credential.id)
        assert.equal(200, status)
        local _, status = http_client.get(spec_helper.API_URL.."/consumers/alice/basic-auth/"..credential.id)
        assert.equal(404, status)
      end)
    end)

    describe("PATCH", function()

      it("[SUCCESS] should update a credential", function()
        local response, status = http_client.patch(BASE_URL..credential.id, { username = "alice" })
        assert.equal(200, status)
        credential = json.decode(response)
        assert.equal("alice", credential.username)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.patch(BASE_URL..credential.id, { username = "" })
        assert.equal(400, status)
        assert.equal('{"username":"username is not a string"}\n', response)
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
