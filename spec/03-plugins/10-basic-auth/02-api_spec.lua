local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: basic-auth (API) [#" .. strategy .. "]", function()
    local consumer
    local admin_client
    local bp
    local db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "basicauth_credentials",
      })

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)
    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then admin_client:close() end
    end)

    describe("/consumers/:consumer/basic-auth/", function()
      lazy_setup(function()
        consumer = bp.consumers:insert({
          username = "bob"
        }, { nulls = true })
      end)
      after_each(function()
        db:truncate("basicauth_credentials")
      end)

      describe("POST", function()
        it("creates a basic-auth credential", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/basic-auth",
            body    = {
              username = "bob",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("bob", json.username)
        end)
        it("creates a basic-auth credential with tags", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/basic-auth/",
            body    = {
              username = "bobby",
              password = "kong",
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
        it("hashes the password", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/basic-auth",
            body    = {
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
          local hash   = crypto.hash(consumer.id, "kong")
          assert.equal(hash, json.password)
        end)
        it("hashes the password without trimming whitespace", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/bob/basic-auth",
            body    = {
              username = "bob",
              password = " kong "
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.is_string(json.password)
          assert.not_equal(" kong ", json.password)

          local crypto = require "kong.plugins.basic-auth.crypto"
          local hash   = crypto.hash(consumer.id, " kong ")
          assert.equal(hash, json.password)
        end)
        describe("errors", function()
          it("returns bad request", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/basic-auth",
              body    = {},
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              username = "required field missing",
              password = "required field missing",
            }, json.fields)
          end)
          it("cannot create two identical usernames", function()
            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/basic-auth",
              body    = {
                username = "bob",
                password = "kong"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(201, res)

            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/consumers/bob/basic-auth",
              body    = {
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

      describe("GET", function()
        lazy_setup(function()
          for i = 1, 3 do
            bp.basicauth_credentials:insert {
              username = "bob" .. i,
              password = "kong",
              consumer = { id = consumer.id },
            }
          end
        end)
        lazy_teardown(function()
          db:truncate("basicauth_credentials")
        end)
        it("retrieves the first page", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/basic-auth"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(3, #json.data)
        end)
      end)
    end)

    describe("/consumers/:consumer/basic-auth/:id", function()
      local credential
      before_each(function()
        db:truncate("basicauth_credentials")
        credential = bp.basicauth_credentials:insert {
          username = "bob",
          password = "kong",
          consumer = { id = consumer.id },
        }
      end)
      describe("GET", function()
        it("retrieves basic-auth credential by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/basic-auth/" .. credential.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(credential.id, json.id)
        end)
        it("retrieves basic-auth credential by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/basic-auth/" .. credential.username
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
            method  = "GET",
            path    = "/consumers/bob/basic-auth/" .. credential.id
          })
          assert.res_status(200, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/consumers/alice/basic-auth/" .. credential.id
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PUT", function()
        it("creates a basic-auth credential", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/basic-auth/robert",
            body    = {
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("robert", json.username)
        end)
        describe("errors", function()
          it("returns bad request", function()
            local res = assert(admin_client:send {
              method  = "PUT",
              path    = "/consumers/bob/basic-auth/b59d82f6-c839-4a60-b491-c6cdff4cd5d3",
              body    = {
                username = 123,
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              username  = "expected a string",
              password = "required field missing",
            }, json.fields)
          end)
        end)
      end)

      describe("PATCH", function()
        it("updates a credential by id", function()
          local previous_hash = credential.password

          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/basic-auth/" .. credential.id,
            body    = {
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
        it("ignores a nil password when updated by id", function()
          local previous_hash = credential.password

          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/basic-auth/" .. credential.id,
            body    = {
              username = "Tyrion Lannister"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("Tyrion Lannister", json.username)
          assert.equal(previous_hash, json.password)
        end)
        it("updates a credential by username", function()
          local previous_hash = credential.password

          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/basic-auth/" .. credential.username,
            body    = {
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
        it("ignores a nil password when updated by username", function()
          local previous_hash = credential.password

          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/basic-auth/" .. credential.username,
            body    = {
              username = "Tyrion Lannister"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("Tyrion Lannister", json.username)
          assert.equal(previous_hash, json.password)
        end)
        describe("errors", function()
          it("handles invalid input", function()
            local res = assert(admin_client:send {
              method  = "PATCH",
              path    = "/consumers/bob/basic-auth/" .. credential.id,
              body    = {
                username = 123
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ username = "expected a string" }, json.fields)
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes a credential", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/basic-auth/" .. credential.id,
          })
          assert.res_status(204, res)
        end)
        describe("errors", function()
          it("returns 404 on missing username", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/basic-auth/blah"
            })
            assert.res_status(404, res)
          end)
          it("returns 404 if not found", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/basic-auth/00000000-0000-0000-0000-000000000000"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
    describe("/basic-auths", function()
      local consumer2
      describe("GET", function()
        lazy_setup(function()
          db:truncate("basicauth_credentials")
          bp.basicauth_credentials:insert {
            consumer = { id = consumer.id },
            username = "bob",
            password = "secret",
          }
          consumer2 = bp.consumers:insert {
            username = "bob-the-buidler"
          }
          bp.basicauth_credentials:insert {
            consumer = { id = consumer2.id },
            username = "bob-the-buidler",
            password = "secret",
          }
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

          assert.not_same(json_1.data, json_2.data)
          -- Disabled: on Cassandra, the last page still returns a
          -- next_page token, and thus, an offset proprty in the
          -- response of the Admin API.
          --assert.is_nil(json_2.offset) -- last page
        end)
      end)

      describe("POST", function()
        lazy_setup(function()
          db:truncate("basicauth_credentials")
        end)

        it("does not create basic-auth credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/basic-auths",
            body = {
              username = "bob",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("2 schema violations (consumer: required field missing; password: required field missing)", json.message)
        end)

        it("creates basic-auth credential", function()
          local res = assert(admin_client:send {
            method = "POST",
            path = "/basic-auths",
            body = {
              username = "bob",
              password = "test",
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

    describe("/basic-auths/:username_or_id", function()
      describe("PATCH", function()
        local consumer2

        lazy_setup(function()
          consumer2 = bp.consumers:insert({
            username = "john"
          })
        end)

        it("does not allow updating consumer as it would invalidate the password", function()
          local res = assert(admin_client:send {
            method = "PATCH",
            path = "/basic-auths/bob",
            body = {
              consumer = {
                id = consumer2.id
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("schema violation (all or none of these fields must be set: 'password', 'consumer.id')", json.message)
        end)
      end)

      describe("PUT", function()
        lazy_setup(function()
          db:truncate("basicauth_credentials")
        end)

        it("does not create basic-auth credential when missing consumer", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/basic-auths/bob",
            body = {
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same("2 schema violations (consumer: required field missing; password: required field missing)", json.message)
        end)

        it("creates basic-auth credential", function()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/basic-auths/bob",
            body = {
              password = "secret",
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

    describe("/basic-auths/:credential_username_or_id/consumer", function()
      describe("GET", function()
        local credential
        lazy_setup(function()
          db:truncate("basicauth_credentials")
          credential = bp.basicauth_credentials:insert {
            consumer = { id = consumer.id },
            username = "bob",
            password = "secret",
          }
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
end
