local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: hmac-auth (API) [#" .. strategy .. "]", function()
    local admin_client
    local consumer
    local bp
    local db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "hmacauth_credentials",
      })

      assert(helpers.start_kong({
        database = strategy,
      }))

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      assert(helpers.stop_kong())
    end)

    describe("/consumers/:consumer/hmac-auth/", function()
      describe("POST", function()
        before_each(function()
          assert(db:truncate("routes"))
          assert(db:truncate("services"))
          assert(db:truncate("consumers"))
          db:truncate("plugins")
          db:truncate("hmacauth_credentials")

          consumer = bp.consumers:insert({
            username  = "bob",
            custom_id = "1234"
          }, { nulls = true })
        end)
        it("[SUCCESS] should create a hmac-auth credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/hmac-auth/",
            body    = {
              username         = "bob",
              secret           = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(201, res)
          local cred = cjson.decode(body)
          assert.equal(consumer.id, cred.consumer.id)
        end)
        it("[SUCCESS] should create a hmac-auth credential with a random secret", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/hmac-auth/",
            body    = {
              username         = "bob",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(201, res)
          local cred = cjson.decode(body)
          assert.is.not_nil(cred.secret)
        end)
        it("[SUCCESS] should create a hmac-auth credential with tags", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/hmac-auth/",
            body    = {
              username = "bobby",
              tags     = { "tag1", "tag2" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("tag1", json.tags[1])
          assert.equal("tag2", json.tags[2])
        end)
        it("[FAILURE] should return proper errors", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/hmac-auth/",
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ username = "required field missing" }, json.fields)
        end)
      end)

      describe("GET", function()
        it("should retrieve all", function()
          bp.hmacauth_credentials:insert{
            consumer = { id = consumer.id },
          }

          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/hmac-auth",
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(1, #(json.data))
        end)
      end)
    end)

    describe("/consumers/:consumer/hmac-auth/:id", function()
      local credential
      before_each(function()
        credential = bp.hmacauth_credentials:insert{
          consumer = { id = consumer.id },
        }
      end)
      describe("GET", function()
        it("should retrieve by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/hmac-auth/" .. credential.id,
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body_json = assert.res_status(200, res)
          local body = cjson.decode(body_json)
          assert.equals(credential.id, body.id)
        end)
        it("should retrieve by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/hmac-auth/" .. credential.username,
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body_json = assert.res_status(200, res)
          local body = cjson.decode(body_json)
          assert.equals(credential.id, body.id)
        end)
      end)

      describe("PATCH", function()
        it("[SUCCESS] should update a credential by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/hmac-auth/" .. credential.id,
            body    = {
              username         = "alice"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body_json = assert.res_status(200, res)
          local cred = cjson.decode(body_json)
          assert.equals("alice", cred.username)
        end)
        it("[SUCCESS] should update a credential by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/hmac-auth/" .. credential.username,
            body    = {
              username         = "aliceUPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body_json = assert.res_status(200, res)
          local cred = cjson.decode(body_json)
          assert.equals("aliceUPD", cred.username)
        end)
        it("[FAILURE] should return proper errors", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/hmac-auth/" .. credential.id,
            body    = {
              username         = ""
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local response = assert.res_status(400, res)
          local json = cjson.decode(response)
          assert.same({ username = "length must be at least 1" }, json.fields)
        end)
      end)

      describe("PUT", function()
        it("[SUCCESS] should create and update", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/hmac-auth/foo",
            body    = {
              secret   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local cred = cjson.decode(body)
          assert.equal("foo", cred.username)
          assert.equal(consumer.id, cred.consumer.id)
        end)
        it("[FAILURE] should return proper errors", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/hmac-auth/foo",
            body    = {
              secret = 123,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ secret = "expected a string" }, json.fields)
        end)
      end)

      describe("DELETE", function()
        it("[FAILURE] should return proper errors", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/hmac-auth/aliceasd",
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)

          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/hmac-auth/00000000-0000-0000-0000-000000000000",
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)
        it("[SUCCESS] should delete a credential", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/hmac-auth/" .. credential.id,
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(204, res)
        end)
      end)
    end)
    describe("/hmac-auths", function()
      local consumer2
      describe("GET", function()
        lazy_setup(function()
          db:truncate("hmacauth_credentials")
          bp.hmacauth_credentials:insert {
            consumer = { id = consumer.id },
            username = "bob"
          }
          consumer2 = bp.consumers:insert {
            username = "bob-the-buidler"
          }
          bp.hmacauth_credentials:insert {
            consumer = { id = consumer2.id },
            username = "bob-the-buidler"
          }
        end)
        it("retrieves all the hmac-auths with trailing slash", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths/"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(2, #json.data)
        end)
        it("retrieves all the hmac-auths without trailing slash", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(2, #json.data)
        end)
        it("paginates through the hmac-auths", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths?size=1",
          })
          local body = assert.res_status(200, res)
          local json_1 = cjson.decode(body)
          assert.is_table(json_1.data)
          assert.equal(1, #json_1.data)

          res = assert(admin_client:send {
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

          assert.not_same(json_1.data, json_2.data)
          -- Disabled: on Cassandra, the last page still returns a
          -- next_page token, and thus, an offset proprty in the
          -- response of the Admin API.
          --assert.is_nil(json_2.offset) -- last page
        end)
      end)

      describe("POST", function()
        lazy_setup(function()
          db:truncate("hmacauth_credentials")
        end)

        it("does not create hmac-auth credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/hmac-auths",
            body = {
              username = "bob",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("schema violation (consumer: required field missing)", json.message)
        end)

        it("creates hmac-auth credential", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/hmac-auths",
            body = {
              username = "bob",
              consumer = {
                id = consumer.id
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("bob", json.username)
        end)
      end)
    end)

    describe("/hmac-auths/:username_or_id", function()
      describe("PUT", function()
        lazy_setup(function()
          db:truncate("hmacauth_credentials")
        end)

        it("does not create hmac-auth credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/hmac-auths/bob",
            body = {
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("schema violation (consumer: required field missing)", json.message)
        end)

        it("creates hmac-auth credential", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/hmac-auths/bob",
            body = {
              consumer = {
                id = consumer.id
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("bob", json.username)
        end)
      end)
    end)

    describe("/hmac-auths/:hmac_username_or_id/consumer", function()
      describe("GET", function()
        local credential
        lazy_setup(function()
          db:truncate("hmacauth_credentials")
          credential = bp.hmacauth_credentials:insert({
            consumer = { id = consumer.id },
            username = "bob"
          })
        end)
        it("retrieve consumer from a hmac-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths/" .. credential.id .. "/consumer"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer,json)
        end)
        it("retrieve consumer from a hmac-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths/" .. credential.username .. "/consumer"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer,json)
        end)
        it("returns 404 for a random non-existing hmac-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths/" .. utils.uuid()  .. "/consumer"
          })
          assert.res_status(404, res)
        end)
        it("returns 404 for a random non-existing hmac-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/hmac-auths/" .. utils.random_string()  .. "/consumer"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end
