local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("OAuth 2 Credentials API", function()
  local BASE_URL, credential, consumer

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/:consumer/oauth2/", function()

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {
          {username = "bob"}
        }
      }
      consumer = fixtures.consumer[1]
      BASE_URL = spec_helper.API_URL.."/consumers/bob/oauth2/"
    end)

    describe("POST", function()

      it("[SUCCESS] should create a oauth2 credential", function()
        local response, status = http_client.post(BASE_URL, {name = "Test APP", redirect_uri = "http://google.com/"})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.post(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"redirect_uri":"redirect_uri is required","name":"name is required"}\n', response)
      end)

    end)

    describe("PUT", function()
      setup(function()
        spec_helper.get_env().dao_factory.keyauth_credentials:delete({id = credential.id})
      end)

      it("[SUCCESS] should create and update", function()
        local response, status = http_client.put(BASE_URL, {redirect_uri = "http://google.com/", name = "Test APP"})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.put(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"redirect_uri":"redirect_uri is required","name":"name is required"}\n', response)
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

  describe("/consumers/:consumer/oauth2/:id", function()

    describe("GET", function()

      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..credential.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(credential.id, body.id)
      end)

    end)

    describe("PATCH", function()

      it("[SUCCESS] should update a credential", function()
        local response, status = http_client.patch(BASE_URL..credential.id, {redirect_uri = "http://getkong.org/"})
        assert.equal(200, status)
        credential = json.decode(response)
        assert.equal("http://getkong.org/", credential.redirect_uri)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.patch(BASE_URL..credential.id, {redirect_uri = ""})
        assert.equal(400, status)
        assert.equal('{"redirect_uri":"redirect_uri is not a url"}\n', response)
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
