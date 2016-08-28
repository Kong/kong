local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: key-auth (API)", function()
  local consumer
  local admin_client
  setup(function()
    assert(helpers.start_kong())
    admin_client = helpers.admin_client()

    consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/key-auth", function()
    describe("POST", function()
      after_each(function()
        helpers.dao:truncate_table("keyauth_credentials")
      end)
      it("creates a key-auth credential with key", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/key-auth",
          body = {
            key = "1234"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("1234", json.key)
      end)
      it("creates a key-auth auto-generating a unique key", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/key-auth",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.is_string(json.key)

        local first_key = json.key
        helpers.dao:truncate_table("keyauth_credentials")

        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/key-auth",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.is_string(json.key)

        assert.not_equal(first_key, json.key)
      end)
    end)

    describe("PUT", function()
      after_each(function()
        helpers.dao:truncate_table("keyauth_credentials")
      end)
      it("creates a key-auth credential with key", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/key-auth",
          body = {
            key = "1234"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("1234", json.key)
      end)
      it("creates a key-auth credential auto-generating the key", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/key-auth",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.is_string(json.key)
      end)
    end)

    describe("GET", function()
      setup(function()
        for i = 1, 3 do
          assert(helpers.dao.keyauth_credentials:insert {
            consumer_id = consumer.id
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_table("keyauth_credentials")
      end)
      it("retrieves the first page", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
    end)
  end)

  describe("/consumers/:consumer/key-auth/:id", function()
    local credential
    before_each(function()
      helpers.dao:truncate_table("keyauth_credentials")
      credential = assert(helpers.dao.keyauth_credentials:insert {
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves key-auth credential by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth/"..credential.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves credential by id only if the credential belongs to the specified consumer", function()
        assert(helpers.dao.consumers:insert {
          username = "alice"
        })

        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth/"..credential.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/key-auth/"..credential.id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/key-auth/"..credential.id,
          body = {
            key = "4321"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("4321", json.key)
      end)
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/key-auth/"..credential.id,
            body = {
              key = 123
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"key":"key is not a string"}]], body)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/key-auth/"..credential.id,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 400 on invalid input", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/key-auth/blah"
          })
          assert.res_status(400, res)
        end)
        it("returns 404 if not found", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/key-auth/00000000-0000-0000-0000-000000000000"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)
