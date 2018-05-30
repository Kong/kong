local cjson = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

describe("Plugin: key-auth (API)", function()
  local consumer
  local admin_client
  local dao
  local bp

  setup(function()
    local _
    bp, _, dao = helpers.get_db_utils()

    assert(dao.apis:insert {
      name         = "keyauth1",
      upstream_url = helpers.mock_upstream_url,
      hosts        = { "keyauth1.test" },
    })
    assert(dao.apis:insert {
      name         = "keyauth2",
      upstream_url = helpers.mock_upstream_url,
      hosts        = { "keyauth2.test" },
    })
    consumer = bp.consumers:insert {
      username = "bob"
    }
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/key-auth", function()
    describe("POST", function()
      after_each(function()
        dao:truncate_table("keyauth_credentials")
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
        dao:truncate_table("keyauth_credentials")

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
        dao:truncate_table("keyauth_credentials")
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
          assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id
          })
        end
      end)
      teardown(function()
        dao:truncate_table("keyauth_credentials")
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
      dao:truncate_table("keyauth_credentials")
      credential = assert(dao.keyauth_credentials:insert {
        consumer_id = consumer.id
      })
    end)
    describe("GET", function()
      it("retrieves key-auth credential by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth/" .. credential.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves key-auth credential by key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth/" .. credential.key
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(credential.id, json.id)
      end)
      it("retrieves credential by id only if the credential belongs to the specified consumer", function()
        bp.consumers:insert {
          username = "alice"
        }

        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/key-auth/" .. credential.id
        })
        assert.res_status(200, res)

        res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/alice/key-auth/" .. credential.id
        })
        assert.res_status(404, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential by id", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/key-auth/" .. credential.id,
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
      it("updates a credential by key", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/key-auth/" .. credential.key,
          body = {
            key = "4321UPD"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("4321UPD", json.key)
      end)
      describe("errors", function()
        it("handles invalid input", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/consumers/bob/key-auth/" .. credential.id,
            body = {
              key = 123
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ key = "key is not a string" }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/key-auth/" .. credential.id,
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 400 on invalid input", function()
          local res = assert(admin_client:send {
            method = "DELETE",
            path = "/consumers/bob/key-auth/blah"
          })
          assert.res_status(404, res)
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
  describe("/apis/:api/plugins", function()
    it("fails with invalid key_names", function()
      local key_name = "hello\\world"
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/keyauth1/plugins",
        body = {
          name = "key-auth",
          config = {
            key_names = {key_name},
          },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.response(res).has.status(400)
      local body = assert.response(res).has.jsonbody()
      assert.equal("'hello\\world' is illegal: bad header name " ..
                   "'hello\\world', allowed characters are A-Z, a-z, 0-9," ..
                   " '_', and '-'", body["config.key_names"])
    end)
    it("succeeds with valid key_names", function()
      local key_name = "hello-world"
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/keyauth2/plugins",
        body = {
          name = "key-auth",
          config = {
            key_names = {key_name},
          },
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.response(res).has.status(201)
      local body = assert.response(res).has.jsonbody()
      assert.equal(key_name, body.config.key_names[1])
    end)
  end)

  describe("/key-auths", function()
    local consumer2

    describe("GET", function()
      setup(function()
        dao:truncate_table("keyauth_credentials")

        for i = 1, 3 do
          assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id
          })
        end

        consumer2 = bp.consumers:insert {
          username = "bob-the-buidler"
        }

        for i = 1, 3 do
          assert(dao.keyauth_credentials:insert {
            consumer_id = consumer2.id
          })
        end
      end)

      it("retrieves all the key-auths with trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths/",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(6, #json.data)
        assert.equal(6, json.total)
      end)
      it("retrieves all the key-auths without trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(6, #json.data)
        assert.equal(6, json.total)
      end)
      it("paginates through the key-auths", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths?size=3",
        })
        local body = assert.res_status(200, res)
        local json_1 = cjson.decode(body)
        assert.is_table(json_1.data)
        assert.equal(3, #json_1.data)
        assert.equal(6, json_1.total)

        res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths",
          query = {
            size = 3,
            offset = json_1.offset,
          }
        })
        body = assert.res_status(200, res)
        local json_2 = cjson.decode(body)
        assert.is_table(json_2.data)
        assert.equal(3, #json_2.data)
        assert.equal(6, json_2.total)

        assert.not_same(json_1.data, json_2.data)
        -- Disabled: on Cassandra, the last page still returns a
        -- next_page token, and thus, an offset proprty in the
        -- response of the Admin API.
        --assert.is_nil(json_2.offset) -- last page
      end)
      it("retrieves key-auths for a consumer_id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths?consumer_id=" .. consumer.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(3, #json.data)
        assert.equal(3, json.total)
      end)
      it("return empty for a non-existing consumer_id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths?consumer_id=" .. utils.uuid(),
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(0, #json.data)
        assert.equal(0, json.total)
      end)
    end)
  end)

  describe("/key-auths/:credential_key_or_id/consumer", function()
    describe("GET", function()
      local credential

      setup(function()
        dao:truncate_table("keyauth_credentials")
        credential = assert(dao.keyauth_credentials:insert {
          consumer_id = consumer.id
        })
      end)

      it("retrieve Consumer from a credential's id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths/" .. credential.id .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer, json)
      end)
      it("retrieve a Consumer from a credential's key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths/" .. credential.key .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer, json)
      end)
      it("returns 404 for a random non-existing id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths/" .. utils.uuid()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
      it("returns 404 for a random non-existing key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/key-auths/" .. utils.random_string()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
