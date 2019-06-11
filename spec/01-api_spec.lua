local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: mtls-auth (API) [#" .. strategy .. "]", function()
    local consumer
    local admin_client
    local bp
    local db
    local route1
    local route2
    local ca

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "certificates",
        "mtls_auth_credentials",
      }, { "mtls-auth", })

      route1 = bp.routes:insert {
        hosts = { "mtlsauth1.test" },
      }

      route2 = bp.routes:insert {
        hosts = { "mtlsauth2.test" },
      }

      consumer = bp.consumers:insert({
        username = "bob"
      }, { nulls = true })

      ca = bp.certificates:insert({
        key = cjson.null,
      })

      assert(helpers.start_kong({
        plugins = "bundled,mtls-auth",
        database = strategy,
      }))

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("/consumers/:consumer/mtls-auth", function()
      describe("POST", function()
        after_each(function()
          db:truncate("mtls_auth_credentials")
        end)

        it("creates a mtls-auth credential with subject name", function()
          local res = assert(admin_client:send({
            method  = "POST",
            path    = "/consumers/bob/mtls-auth",
            body    = {
              subject_name   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("1234", json.subject_name)
        end)

        it("subject_name is required", function()
          local res = assert(admin_client:send({
            method  = "POST",
            path    = "/consumers/bob/mtls-auth",
            body    = {},
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          local body = assert.res_status(400, res)
          assert.matches("subject_name: required field missing", body, nil, true)
        end)

        it("duplicates not allowed", function()
          local res = assert(admin_client:send({
            method  = "POST",
            path    = "/consumers/bob/mtls-auth",
            body    = {
              subject_name   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal(consumer.id, json.consumer.id)
          assert.equal("1234", json.subject_name)

          -- second time

          res = assert(admin_client:send({
            method  = "POST",
            path    = "/consumers/bob/mtls-auth",
            body    = {
              subject_name   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          }))
          body = assert.res_status(409, res)
          assert.matches("unique constraint violation", body, nil, true)
        end)
      end)

      describe("GET", function()
        lazy_setup(function()
          for i = 1, 3 do
            assert(db.mtls_auth_credentials:insert {
              consumer = { id = consumer.id },
              subject_name = "foo" .. i,
            })
          end

          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers"
          })
          local body = assert.res_status(200, res)
        end)

        lazy_teardown(function()
          db:truncate("mtls_auth_credentials")
        end)

        it("retrieves the first page", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/mtls-auth"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(3, #json.data)
        end)
      end)
    end)

    describe("/consumers/:consumer/mtls-auth/:id", function()
      local credential
      before_each(function()
        db:truncate("mtls_auth_credentials")
        credential = db.mtls_auth_credentials:insert {
          consumer = { id = consumer.id },
          subject_name = "foo",
        }
      end)

      describe("GET", function()
        it("retrieves mtls-auth credential by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/mtls-auth/" .. credential.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(credential.id, json.id)
        end)

        it("retrieves credential by id only if the credential belongs to the specified consumer", function()
          assert(bp.consumers:insert {
            username = "alice"
          })

          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/bob/mtls-auth/" .. credential.id
          })
          assert.res_status(200, res)

          res = assert(admin_client:send {
            method = "GET",
            path   = "/consumers/alice/mtls-auth/" .. credential.id
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PUT", function()
        lazy_setup(function()
          db:truncate("mtls_auth_credentials")
        end)

        it("creates a mtls-auth credential if id does not exist", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/mtls-auth/c16bbff7-5d0d-4a28-8127-1ee581898f11",
            body    = {
              subject_name = "bar",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          cred = cjson.decode(body)
          assert.equal(consumer.id, cred.consumer.id)
          assert.equal("bar", cred.subject_name)
          assert.equal("c16bbff7-5d0d-4a28-8127-1ee581898f11", cred.id)
        end)

        it("updates existing mtls-auth credential if id exists", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/bob/mtls-auth/c16bbff7-5d0d-4a28-8127-1ee581898f11",
            body    = {
              subject_name = "baz",
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          cred = cjson.decode(body)
          assert.equal(consumer.id, cred.consumer.id)
          assert.equal("baz", cred.subject_name)
          assert.equal("c16bbff7-5d0d-4a28-8127-1ee581898f11", cred.id)
        end)
      end)

      describe("PATCH", function()
        it("updates a credential by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/bob/mtls-auth/" .. credential.id,
            body    = { subject_name = "4321" },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("4321", json.subject_name)
        end)

        describe("errors", function()
          it("handles invalid input", function()
            local res = assert(admin_client:send {
              method  = "PATCH",
              path    = "/consumers/bob/mtls-auth/" .. credential.id,
              body    = { subject_name = 123 },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ subject_name = "expected a string" }, json.fields)
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes a credential", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/bob/mtls-auth/" .. credential.id,
          })

          assert.res_status(204, res)
        end)

        describe("errors", function()
          it("returns 400 on invalid input", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/mtls-auth/blah"
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ id = "expected a valid UUID" }, json.fields)
          end)

          it("returns 404 if not found", function()
            local res = assert(admin_client:send {
              method  = "DELETE",
              path    = "/consumers/bob/mtls-auth/00000000-0000-0000-0000-000000000000"
            })
            assert.res_status(404, res)
          end)

        end)
      end)
    end)

    describe("/plugins for route", function()
      it("fails with no certificate_authority", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "mtls-auth",
            route = { id = route1.id },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ certificate_authorities = "required field missing" }, json.fields.config)
      end)

      it("succeeds with valid certificate_authority", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            route = { id = route2.id },
            name       = "mtls-auth",
            config     = {
              certificate_authorities = { ca.id, },
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.same({ ca.id, }, json.config.certificate_authorities)
      end)
    end)

    describe("/mtls-auths", function()
      local consumer2

      describe("GET", function()
        lazy_setup(function()
          db:truncate("mtls_auth_credentials")

          for i = 1, 3 do
            db.mtls_auth_credentials:insert {
              consumer = { id = consumer.id },
              subject_name = "foo" .. i,
            }
          end

          consumer2 = bp.consumers:insert {
            username = "bob-the-buidler",
          }

          for i = 1, 3 do
            db.mtls_auth_credentials:insert {
              consumer = { id = consumer2.id },
              subject_name = "bar" .. i,
            }
          end
        end)

        it("retrieves all the mtls-auths with trailing slash", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths/",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(6, #json.data)
        end)

        it("retrieves all the mtls-auths without trailing slash", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(6, #json.data)
        end)

        it("paginates through the mtls-auths", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths?size=3",
          })
          local body = assert.res_status(200, res)
          local json_1 = cjson.decode(body)
          assert.is_table(json_1.data)
          assert.equal(3, #json_1.data)

          res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths",
            query = {
              size = 3,
              offset = json_1.offset,
            }
          })
          body = assert.res_status(200, res)
          local json_2 = cjson.decode(body)
          assert.is_table(json_2.data)
          assert.equal(3, #json_2.data)

          assert.not_same(json_1.data, json_2.data)
          -- Disabled: on Cassandra, the last page still returns a
          -- next_page token, and thus, an offset proprty in the
          -- response of the Admin API.
          --assert.is_nil(json_2.offset) -- last page
        end)
      end)
    end)

    describe("/mtls-auths/:credential_id/consumer", function()
      describe("GET", function()
        local credential

        lazy_setup(function()
          db:truncate("mtls_auth_credentials")
          credential = db.mtls_auth_credentials:insert {
            consumer = { id = consumer.id },
            subject_name = "foo",
          }
        end)

        it("retrieve Consumer from a credential's id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths/" .. credential.id .. "/consumer"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer, json)
        end)

        it("returns 404 for a random non-existing id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/mtls-auths/" .. utils.uuid()  .. "/consumer"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end
