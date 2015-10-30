local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

local jwt_secrets = spec_helper.get_env().dao_factory.jwt_secrets

describe("JWT API", function()
  local BASE_URL, consumer, jwt_secret

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/:consumer/jwt/", function()

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {{username = "bob"}}
      }
      consumer = fixtures.consumer[1]
      BASE_URL = spec_helper.API_URL.."/consumers/bob/jwt/"
    end)

    describe("POST", function()
      local jwt1, jwt2

      teardown(function()
        jwt_secrets:delete(jwt1)
        jwt_secrets:delete(jwt2)
      end)

      it("[SUCCESS] should create a jwt secret", function()
        local response, status = http_client.post(BASE_URL)
        assert.equal(201, status)
        local body = json.decode(response)
        assert.equal(consumer.id, body.consumer_id)

        jwt1 = body
      end)

      it("[SUCCESS] should accepty any given `secret` and `key` parameters", function()
        local response, status = http_client.post(BASE_URL, {key = "bob2", secret = "tooshort"})
        assert.equal(201, status)
        local body = json.decode(response)
        assert.equal("bob2", body.key)
        assert.equal("tooshort", body.secret)

        jwt2 = body
      end)

    end)

    describe("PUT", function()

      it("[SUCCESS] should create and update", function()
        local response, status = http_client.put(BASE_URL)
        assert.equal(201, status)
        local body = json.decode(response)
        assert.equal(consumer.id, body.consumer_id)

        -- For GET tests
        jwt_secret = body
      end)

    end)

    describe("GET", function()

      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equal(1, #(body.data))
      end)

    end)
  end)

  describe("/consumers/:consumer/jwt/:id", function()

    describe("GET", function()

      it("should retrieve by id", function()
        local _, status = http_client.get(BASE_URL..jwt_secret.id)
        assert.equal(200, status)
      end)

    end)

    describe("PATCH", function()

      it("[SUCCESS] should update a credential", function()
        local response, status = http_client.patch(BASE_URL..jwt_secret.id, {key = "alice",secret = "newsecret"})
        assert.equal(200, status)
        jwt_secret = json.decode(response)
        assert.equal("newsecret", jwt_secret.secret)
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
        local _, status = http_client.delete(BASE_URL..jwt_secret.id)
        assert.equal(204, status)
      end)

    end)
  end)
end)
