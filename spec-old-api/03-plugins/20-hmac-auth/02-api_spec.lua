local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

describe("Plugin: hmac-auth (API)", function()
  local client, credential, consumer
  local bp
  local db
  local dao

  setup(function()
    bp, db, dao = helpers.get_db_utils()

    helpers.prepare_prefix()
    assert(helpers.start_kong())
    client = helpers.admin_client()
  end)

  teardown(function()
    if client then client:close() end
    assert(helpers.stop_kong())
    helpers.clean_prefix()
  end)

  describe("/consumers/:consumer/hmac-auth/", function()
    describe("POST", function()
      before_each(function()
        assert(db:truncate("routes"))
        assert(db:truncate("services"))
        assert(db:truncate("consumers"))
        assert(db:truncate("plugins"))
        dao:truncate_table("apis")
        dao:truncate_table("hmacauth_credentials")

        consumer = bp.consumers:insert {
          username = "bob",
          custom_id = "1234"
        }
      end)
      it("[SUCCESS] should create a hmac-auth credential", function()
        local res = assert(client:send {
          method = "POST",
          path = "/consumers/bob/hmac-auth/",
          body = {
            username = "bob",
            secret = "1234"
          },
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(201, res)
        credential = cjson.decode(body)
        assert.equal(consumer.id, credential.consumer_id)
      end)
      it("[SUCCESS] should create a hmac-auth credential with a random secret", function()
        local res = assert(client:send {
          method = "POST",
          path = "/consumers/bob/hmac-auth/",
          body = {
            username = "bob",
          },
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(201, res)
        credential = cjson.decode(body)
        assert.is.not_nil(credential.secret)
      end)
      it("[FAILURE] should return proper errors", function()
        local res = assert(client:send {
          method = "POST",
          path = "/consumers/bob/hmac-auth/",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.res_status(400, res)
        assert.equal('{"username":"username is required"}', body)
      end)
    end)

    describe("PUT", function()
      it("[SUCCESS] should create and update", function()
        local res = assert(client:send {
          method = "PUT",
          path = "/consumers/bob/hmac-auth/",
          body = {
            username = "bob",
            secret = "1234"
          },
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.res_status(201, res)
        credential = cjson.decode(body)
        assert.equal(consumer.id, credential.consumer_id)
      end)
      it("[FAILURE] should return proper errors", function()
        local res = assert(client:send {
          method = "PUT",
          path = "/consumers/bob/hmac-auth/",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.res_status(400, res)
        assert.equal('{"username":"username is required"}', body)
      end)
    end)

    describe("GET", function()
      it("should retrieve all", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/bob/hmac-auth/",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        local body = cjson.decode(body_json)
        assert.equal(1, #(body.data))
      end)
    end)
  end)

  describe("/consumers/:consumer/hmac-auth/:id", function()
    describe("GET", function()
      it("should retrieve by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/bob/hmac-auth/" .. credential.id,
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        local body = cjson.decode(body_json)
        assert.equals(credential.id, body.id)
      end)
      it("should retrieve by username", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/bob/hmac-auth/" .. credential.username,
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        local body = cjson.decode(body_json)
        assert.equals(credential.id, body.id)
      end)
    end)

    describe("PATCH", function()
      it("[SUCCESS] should update a credential by id", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/consumers/bob/hmac-auth/" .. credential.id,
          body = {username = "alice"},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        credential = cjson.decode(body_json)
        assert.equals("alice", credential.username)
      end)
      it("[SUCCESS] should update a credential by username", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/consumers/bob/hmac-auth/" .. credential.username,
          body = {username = "aliceUPD"},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        credential = cjson.decode(body_json)
        assert.equals("aliceUPD", credential.username)
      end)
      it("[FAILURE] should return proper errors", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/consumers/bob/hmac-auth/" .. credential.id,
          body = {username = ""},
          headers = {["Content-Type"] = "application/json"}
        })
        local response = assert.res_status(400, res)
        assert.equal('{"username":"username is required"}', response)
      end)
    end)

    describe("DELETE", function()
      it("[FAILURE] should return proper errors", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/consumers/bob/hmac-auth/aliceasd",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(404, res)

        local res = assert(client:send {
          method = "DELETE",
          path = "/consumers/bob/hmac-auth/00000000-0000-0000-0000-000000000000",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(404, res)
      end)
      it("[SUCCESS] should delete a credential", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/consumers/bob/hmac-auth/" .. credential.id,
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(204, res)
      end)
    end)
  end)
  describe("/hmac-auths", function()
    local consumer2
    describe("GET", function()
      setup(function()
        dao:truncate_table("hmacauth_credentials")
        assert(dao.hmacauth_credentials:insert {
          consumer_id = consumer.id,
          username = "bob"
        })
        consumer2 = bp.consumers:insert {
          username = "bob-the-buidler"
        }
        assert(dao.hmacauth_credentials:insert {
          consumer_id = consumer2.id,
          username = "bob-the-buidler"
        })
      end)
      it("retrieves all the hmac-auths with trailing slash", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("retrieves all the hmac-auths without trailing slash", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("paginates through the hmac-auths", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths?size=1",
        })
        local body = assert.res_status(200, res)
        local json_1 = cjson.decode(body)
        assert.is_table(json_1.data)
        assert.equal(1, #json_1.data)
        assert.equal(2, json_1.total)

        res = assert(client:send {
          method = "GET",
          path = "/hmac-auths",
          query = {
            size = 1,
            offset = json_1.offset,
          }
        })
        body = assert.res_status(200, res)
        local json_2 = cjson.decode(body)
        assert.is_table(json_2.data)
        assert.equal(1, #json_2.data)
        assert.equal(2, json_2.total)

        assert.not_same(json_1.data, json_2.data)
        -- Disabled: on Cassandra, the last page still returns a
        -- next_page token, and thus, an offset proprty in the
        -- response of the Admin API.
        --assert.is_nil(json_2.offset) -- last page
      end)
      it("retrieve hmac-auths for a consumer_id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths?consumer_id=" .. consumer.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
      end)
      it("return empty for a non-existing consumer_id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths?consumer_id=" .. utils.uuid(),
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(0, #json.data)
        assert.equal(0, json.total)
      end)
    end)
  end)
  describe("/hmac-auths/:hmac_username_or_id/consumer", function()
    describe("GET", function()
      local credential
      setup(function()
        dao:truncate_table("hmacauth_credentials")
        credential = assert(dao.hmacauth_credentials:insert {
          consumer_id = consumer.id,
          username = "bob"
        })
      end)
      it("retrieve consumer from a hmac-auth id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths/" .. credential.id .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("retrieve consumer from a hmac-auth username", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths/" .. credential.username .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("returns 404 for a random non-existing hmac-auth id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths/" .. utils.uuid()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
      it("returns 404 for a random non-existing hmac-auth username", function()
        local res = assert(client:send {
          method = "GET",
          path = "/hmac-auths/" .. utils.random_string()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
