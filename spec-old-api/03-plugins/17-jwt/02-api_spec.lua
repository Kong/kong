local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local fixtures = require "spec-old-api.03-plugins.17-jwt.fixtures"

describe("Plugin: jwt (API)", function()
  local admin_client, consumer, jwt_secret
  local dao
  local bp
  local _
  local jwt_secrets

  setup(function()
    bp, _, dao = helpers.get_db_utils()
    jwt_secrets = dao.jwt_secrets

    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("/consumers/:consumer/jwt/", function()
    setup(function()
      consumer = bp.consumers:insert {
        username = "bob"
      }
      bp.consumers:insert {
        username = "alice"
      }
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
      it("accepts duplicate `secret` parameters across jwt_secrets", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/alice/jwt/",
          body = {
            key = "alice",
            secret = "foobarbaz"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("alice", body.key)
        assert.equal("foobarbaz", body.secret)
        jwt1 = body

        res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bobsyouruncle",
            secret = "foobarbaz"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        body = cjson.decode(assert.res_status(201, res))
        assert.equal("bobsyouruncle", body.key)
        assert.equal("foobarbaz", body.secret)
        jwt2 = body

        assert.equals(jwt1.secret, jwt2.secret)
      end)
      it("accepts a valid public key for RS256 when posted urlencoded", function()
        local rsa_public_key = fixtures.rs256_public_key
        rsa_public_key = rsa_public_key:gsub("\n", "\r\n")
        rsa_public_key = rsa_public_key:gsub("([^%w %-%_%.%~])",
          function(c) return string.format ("%%%02X", string.byte(c)) end)
        rsa_public_key = rsa_public_key:gsub(" ", "+")

        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob3",
            algorithm = "RS256",
            rsa_public_key = rsa_public_key
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.equal("bob3", json.key)
      end)
      it("accepts a valid public key for RS256 when posted as json", function()
        local rsa_public_key = fixtures.rs256_public_key

        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob4",
            algorithm = "RS256",
            rsa_public_key = rsa_public_key
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.equal("bob4", json.key)
      end)
      it("fails with missing `rsa_public_key` parameter for RS256 algorithms", function ()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob5",
            algorithm = "RS256"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody()
        assert.equal("no mandatory 'rsa_public_key'", json.message)
      end)
      it("fails with an invalid rsa_public_key for RS256 algorithms", function ()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob5",
            algorithm = "RS256",
            rsa_public_key = "test",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(400)
        local json = assert.response(res).has.jsonbody()
        assert.equal("'rsa_public_key' format is invalid", json.message)
      end)
      it("does not fail when `secret` parameter for HS256 algorithms is missing", function ()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/consumers/bob/jwt/",
          body = {
            key = "bob5",
            algorithm = "HS256",
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.response(res).has.status(201)
        local json = assert.response(res).has.jsonbody()
        assert.string(json.secret)
        assert.equals(32, #json.secret)
        assert.matches("^[%a%d]+$", json.secret)
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
        assert.equal(6, #(body.data))
      end)
    end)
  end)

  describe("/consumers/:consumer/jwt/:id", function()
    describe("GET", function()
      it("retrieves by id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/jwt/" .. jwt_secret.id,
        })
        assert.res_status(200, res)
      end)
      it("retrieves by key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/consumers/bob/jwt/" .. jwt_secret.key,
        })
        assert.res_status(200, res)
      end)
    end)

    describe("PATCH", function()
      it("updates a credential by id", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/jwt/" .. jwt_secret.id,
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
      it("updates a credential by key", function()
        local res = assert(admin_client:send {
          method = "PATCH",
          path = "/consumers/bob/jwt/" .. jwt_secret.key,
          body = {
            key = "alice",
            secret = "newsecret2"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        jwt_secret = cjson.decode(body)
        assert.equal("newsecret2", jwt_secret.secret)
      end)
    end)

    describe("DELETE", function()
      it("deletes a credential", function()
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/jwt/" .. jwt_secret.id,
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
          path = "/consumers/bob/jwt/" .. "blah",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(404, res)

       local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/bob/jwt/" .. "00000000-0000-0000-0000-000000000000",
          body = {},
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(404, res)
      end)
    end)
  end)
  describe("/jwts", function()
    local consumer2
    describe("GET", function()
      setup(function()
        dao:truncate_table("jwt_secrets")
        assert(dao.jwt_secrets:insert {
          consumer_id = consumer.id,
        })
        consumer2 = bp.consumers:insert {
          username = "bob-the-buidler"
        }
        assert(dao.jwt_secrets:insert {
          consumer_id = consumer2.id,
        })
      end)
      it("retrieves all the jwts with trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts/"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("retrieves all the jwts without trailing slash", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(2, #json.data)
        assert.equal(2, json.total)
      end)
      it("paginates through the jwts", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts?size=1",
        })
        local body = assert.res_status(200, res)
        local json_1 = cjson.decode(body)
        assert.is_table(json_1.data)
        assert.equal(1, #json_1.data)
        assert.equal(2, json_1.total)

        res = assert(admin_client:send {
          method = "GET",
          path = "/jwts",
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
      it("retrieve jwts for a consumer_id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts?consumer_id=" .. consumer.id
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
          path = "/jwts?consumer_id=" .. utils.uuid(),
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.data)
        assert.equal(0, #json.data)
        assert.equal(0, json.total)
      end)
    end)
  end)
  describe("/jwts/:jwt_key_or_id/consumer", function()
    describe("GET", function()
      local credential
      setup(function()
        dao:truncate_table("jwt_secrets")
        credential = assert(dao.jwt_secrets:insert {
          consumer_id = consumer.id
        })
      end)
      it("retrieve consumer from a JWT id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts/" .. credential.id .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("retrieve consumer from a JWT key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts/" .. credential.key .. "/consumer"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(consumer,json)
      end)
      it("returns 404 for a random non-existing JWT id", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts/" .. utils.uuid()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
      it("returns 404 for a random non-existing JWT key", function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/jwts/" .. utils.random_string()  .. "/consumer"
        })
        assert.res_status(404, res)
      end)
    end)
  end)
end)
