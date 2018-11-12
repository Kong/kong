local cjson = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

describe("Plugin: basic-auth (API)", function()
  local consumer, admin_client
  local dao

  setup(function()
    dao = select(3, helpers.get_db_utils())

    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/basic-auth/", function()
    setup(function()
      consumer = assert(dao.consumers:insert {
        username = "bob"
      })
    end)
    after_each(function()
      dao:truncate_table("basicauth_credentials")
    end)

    describe("POST", function()
      it("creates a basic-auth credential", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/basic-auth",
          body = {
            username = "bob",
            password = "kong"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("bob", json.username)
      end)
      it("encrypts the password", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/basic-auth",
          body = {
            username = "bob",
            password = "kong"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.is_string(json.password)
        assert.not_equal("kong", json.password)

        local crypto = require "kong.plugins.basic-auth.crypto"
        local hash = crypto.encrypt {
          consumer_id = consumer.id,
          password = "kong"
        }
        assert.equal(hash, json.password)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/basic-auth",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ username = "username is required" }, json)
        end)
        it("cannot create two identical usernames", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/basic-auth",
            body = {
              username = "bob",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          assert.res_status(201, res)

          local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/bob/basic-auth",
            body = {
              username = "bob",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(409, res)
        end)
      end)
    end)

    describe("PUT", function()
      it("creates a basic-auth credential", function()
        local res = assert(admin_client:send {
          method = "PUT",
          path = "/consumers/bob/basic-auth",
          body = {
            username = "bob",
            password = "kong"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(consumer.id, json.consumer_id)
        assert.equal("bob", json.username)
      end)
      describe("errors", function()
        it("returns bad request", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/consumers/bob/basic-auth",
            body = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ username = "username is required" }, json)
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        for i = 1, 3 do
          assert(dao.basicauth_credentials:insert {
            username = "bob" .. i,
            password = "kong",
            consumer_id = consumer.id
          })
        end
      end)
      teardown(function()
        dao:truncate_table("basicauth_credentials")
      end)
      it("retrieves the first page", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
    end)
  end)

  describe("/consumers/:consumer/basic-auth/:id", function()
    local credential
    before_each(function()
      dao:truncate_table("basicauth_credentials")
      credential = assert(dao.basicauth_credentials:insert {
        username = "bob",
        password = "kong",
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves basic-auth credential by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. credential.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves basic-auth credential by username", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. credential.username
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves credential by id only if the credential belongs to the specified consumer", function()
        assert(dao.consumers:insert {
          username = "alice"
        })

        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/basic-auth/" .. credential.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/basic-auth/" .. credential.id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential by id", function()
        local previous_hash = credential.password

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/basic-auth/" .. credential.id,
          body = {
            password = "4321"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_hash, json.password)
      end)
      it("updates a credential by username", function()
        local previous_hash = credential.password

        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/basic-auth/" .. credential.username,
          body = {
            password = "upd4321"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.not_equal(previous_hash, json.password)
      end)
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/basic-auth/" .. credential.id,
            body = {
              password = 123
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ password = "password is not a string" }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/basic-auth/" .. credential.id,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 404 on missing username", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/basic-auth/blah"
          })
          assert.res_status(404, res)
        end)
        it("returns 404 if not found", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/basic-auth/00000000-0000-0000-0000-000000000000"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
  describe("/basic-auths", function()
    local consumer2
    describe("GET", function()
      setup(function()
        dao:truncate_table("basicauth_credentials")
        assert(dao.basicauth_credentials:insert {
          consumer_id = consumer.id,
          username = "bob"
        })
        consumer2 = assert(dao.consumers:insert {
          username = "bob-the-buidler"
        })
        assert(dao.basicauth_credentials:insert {
          consumer_id = consumer2.id,
          username = "bob-the-buidler"
        })
      end)
      it("retrieves all the basic-auths with trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("retrieves all the basic-auths without trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("paginates through the basic-auths", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths?size=1",
        })
        local body = assert.res_status(200, res)
        local json_1 = cjson.decode(body)
        assert.is_table(json_1.data)
        assert.equal(1, #json_1.data)
        assert.equal(2, json_1.total)

        res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths",
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
      it("retrieve basic-auths for a consumer_id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths?consumer_id=" .. consumer.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(1, #json.data)
        assert.equal(1, json.total)
      end)
      it("return empty for a non-existing consumer_id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths?consumer_id=" .. utils.uuid(),
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(0, #json.data)
        assert.equal(0, json.total)
      end)
    end)
  end)
  describe("/basic-auths/:credential_username_or_id/consumer", function()
    describe("GET", function()
      local credential
      setup(function()
        dao:truncate_table("basicauth_credentials")
        credential = assert(dao.basicauth_credentials:insert {
          consumer_id = consumer.id,
          username = "bob"
        })
      end)
      it("retrieve consumer from a basic-auth id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths/" .. credential.id .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("retrieve consumer from a basic-auth username", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths/" .. credential.username .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("returns 404 for a random non-existing basic-auth id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths/" .. utils.uuid()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
      it("returns 404 for a random non-existing basic-auth username", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/basic-auths/" .. utils.random_string()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
