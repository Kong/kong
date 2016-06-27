local helpers = require "spec.helpers"
local cjson = require "cjson"

local jwt_secrets = helpers.dao.jwt_secrets

describe("Plugin: jwt (API)", function()
  local admin_client, consumer, jwt_secret
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/jwt/", function()
    setup(function()
      consumer = assert(helpers.dao.consumers:insert {
        username = "bob"
      })
    end)

    describe("POST", function()
      local jwt1, jwt2
      teardown(function()
        if jwt1 == nil then return end
        jwt_secrets:delete(jwt1)
        jwt_secrets:delete(jwt2)
      end)

      it("creates a jwt secret", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)
        jwt1 = body
      end)
      it("accepts any given `secret` and `key` parameters", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob2",
            secret = "tooshort"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("bob2", body.key)
        assert.equal("tooshort", body.secret)
        jwt2 = body
      end)
    end)

    describe("PUT", function()
      it("creates and update", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(consumer.id, body.consumer_id)

        -- For GET tests
        jwt_secret = body
      end)
    end)

    describe("GET", function()
      it("retrieves all", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/jwt/",
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(1, #(body.data))
      end)
    end)
  end)

  describe("/consumers/:consumer/jwt/:id", function()
    describe("GET", function()
      it("retrieves by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/jwt/"..jwt_secret.id,
        })
        assert.res_status(200, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/jwt/"..jwt_secret.id,
          body = {
            key = "alice",
            secret = "newsecret"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        jwt_secret = cjson.decode(body)
        assert.equal("newsecret", jwt_secret.secret)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/jwt/"..jwt_secret.id,
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(204, res)
      end)
      it("returns proper errors", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/jwt/".."blah",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(400, res)

       local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/jwt/".."00000000-0000-0000-0000-000000000000",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
