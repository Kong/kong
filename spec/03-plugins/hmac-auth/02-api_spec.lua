local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: hmac-auth (API)", function()
  local client, credential, consumer
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())

    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/hmac-auth/", function()
    describe("POST", function()
      before_each(function()
        helpers.dao:truncate_tables()
        consumer = assert(helpers.dao.consumers:insert {
          username = "bob",
          custom_id = "1234"
        })
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
          path = "/consumers/bob/hmac-auth/"..credential.id,
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        local body = cjson.decode(body_json)
        assert.equals(credential.id, body.id)
      end)
    end)

    describe("PATCH", function()
      it("[SUCCESS] should update a credential", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/consumers/bob/hmac-auth/"..credential.id,
          body = {username = "alice"},
          headers = {["Content-Type"] = "application/json"}
        })
        local body_json = assert.res_status(200, res)
        credential = cjson.decode(body_json)
        assert.equals("alice", credential.username)
      end)
      it("[FAILURE] should return proper errors", function()
        local res = assert(client:send {
          method = "PATCH",
          path = "/consumers/bob/hmac-auth/"..credential.id,
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
          path = "/consumers/bob/hmac-auth/alice",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(400, res)

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
          path = "/consumers/bob/hmac-auth/"..credential.id,
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })
        assert.res_status(204, res)
      end)
    end)
  end)
end)
