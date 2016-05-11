local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"

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
      it("[SUCCESS] should create a oauth2 credential with several redirect_uris", function()
        local response, status = http_client.post(BASE_URL, {name = "Test APP", redirect_uri = "http://google.com/,http://aaa.com"})
        assert.equal(201, status)
        credential = json.decode(response)
        assert.equal(consumer.id, credential.consumer_id)
        assert.equal(2, utils.table_size(credential.redirect_uri))
      end)
      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.post(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"redirect_uri":"redirect_uri is required","name":"name is required"}\n', response)
      end)
      it("[FAILURE] should return redirect_uris errors", function()
        local response, status = http_client.post(BASE_URL, {name = "Test App", redirect_uri = "not-valid"})
        assert.equal(400, status)
        local output = json.decode(response)
        assert.equal(output.redirect_uri, "cannot parse 'not-valid'")

        local response2, status2 = http_client.post(BASE_URL, {name = "Test App", redirect_uri = "http://test.com/#with-fragment"})
        assert.equal(400, status2)
        local output2 = json.decode(response2)
        assert.equal(output2.redirect_uri, "fragment not allowed in 'http://test.com/#with-fragment'")

        -- same tests but with multiple redirect_uris
        local response3, status3 = http_client.post(BASE_URL, {name = "Test App", redirect_uri = {"http://valid.com", "not-valid"}})
        assert.equal(400, status3)
        local output3 = json.decode(response3)
        assert.equal(output3.redirect_uri, "cannot parse 'not-valid'")

        local response4, status4 = http_client.post(BASE_URL, {name = "Test App", redirect_uri = {"http://valid.com", "http://test.com/#with-fragment"}})
        assert.equal(400, status4)
        local output4 = json.decode(response4)
        assert.equal(output4.redirect_uri, "fragment not allowed in 'http://test.com/#with-fragment'")
      end)
    end)

    describe("PUT", function()
      setup(function()
        local credentials = spec_helper.get_env().dao_factory.keyauth_credentials
        credentials:delete({id = credential.id})
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
        assert.equal(3, #(body.data))
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
        assert.equal("http://getkong.org/", credential.redirect_uri[1])
      end)
      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.patch(BASE_URL..credential.id, {redirect_uri = ""})
        assert.equal(400, status)
        assert.equal('{"redirect_uri":"redirect_uri is not a array"}\n', response)
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

  describe("/oauth2_tokens/", function()

    -- Create credential
    local response, status = http_client.post(BASE_URL, {name = "Test APP", redirect_uri = "http://google.com/"})
    assert.equal(201, status)
    credential = json.decode(response)

    local token

    BASE_URL = spec_helper.API_URL.."/oauth2_tokens/"

    describe("POST", function()
      it("[SUCCESS] should create a oauth2 token", function()
        local response, status = http_client.post(BASE_URL, {credential_id = credential.id, expires_in = 10})
        assert.equal(201, status)
        token = json.decode(response)
        assert.equal(credential.id, token.credential_id)
        assert.equal(10, token.expires_in)
        assert.truthy(token.access_token)
        assert.falsy(token.refresh_token)
        assert.equal("bearer", token.token_type)
      end)
      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.post(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"credential_id":"credential_id is required","expires_in":"expires_in is required"}\n', response)
      end)
    end)

    describe("PUT", function()
      it("#only [SUCCESS] should create a oauth2 token", function()
        local response, status = http_client.put(BASE_URL, {credential_id = credential.id, expires_in = 10})
        assert.equal(201, status)
        token = json.decode(response)
        assert.equal(credential.id, token.credential_id)
        assert.equal(10, token.expires_in)
        assert.truthy(token.access_token)
        assert.falsy(token.refresh_token)
        assert.equal("bearer", token.token_type)
      end)
      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.put(BASE_URL, {})
        assert.equal(400, status)
        assert.equal('{"credential_id":"credential_id is required","expires_in":"expires_in is required"}\n', response)
      end)
    end)

    describe("GET", function()
      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..token.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(credential.id, body.credential_id)
      end)
      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(2, body.total)
      end)
    end)

    describe("PATCH", function()
      it("should update partial fields", function()
        local response, status = http_client.patch(BASE_URL..token.id, { access_token = "helloworld" })
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals("helloworld", body.access_token)
        assert.falsy(body.refresh_token)

        -- Check it has really been updated
        response, status = http_client.get(BASE_URL..token.id)
        assert.equal(200, status)
        body = json.decode(response)
        assert.equals("helloworld", body.access_token)
        assert.falsy(body.refresh_token)
      end)

      describe("PUT", function()
        it("should update every field", function()
          local response, status = http_client.get(BASE_URL..token.id)
          assert.equal(200, status)
          local body = json.decode(response)
          body.refresh_token = nil
          body.access_token = "helloworld"

          local response, status = http_client.put(BASE_URL..token.id, body)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.equals("helloworld", body.access_token)
          assert.falsy(body.refresh_token)

          -- Check it has really been updated
          response, status = http_client.get(BASE_URL..token.id)
          assert.equal(200, status)
          body = json.decode(response)
          assert.equals("helloworld", body.access_token)
          assert.falsy(body.refresh_token)
        end)
      end)
    end)

     describe("PUT", function()
      it("should update the entire object", function()
        local response, status = http_client.get(BASE_URL..token.id)
        assert.equal(200, status)
        local body = json.decode(response)
        body.access_token = "puthelloworld"
        body.created_at = nil

        response, status = http_client.put(BASE_URL..token.id, body)
        assert.equal(200, status)
        body = json.decode(response)
        assert.equals("puthelloworld", body.access_token)

        -- Check it has really been updated
        response, status = http_client.get(BASE_URL..token.id)
        assert.equal(200, status)
        body = json.decode(response)
        assert.equals("puthelloworld", body.access_token)
      end)
    end)
  end)
end)
