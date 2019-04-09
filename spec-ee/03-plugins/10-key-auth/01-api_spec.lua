local cjson   = require "cjson"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy() do
  pending("Pending on feature flags - Plugin (EE logic): key-auth (API) [" .. strategy .. "]", function()
    local admin_client
    local dao
    local admin, consumer, developer
    local admin_credential, developer_credential, consumer_credential

    setup(function()
      local bp, _
      bp, _, dao = helpers.get_db_utils(strategy)

      consumer = bp.consumers:insert {
        username = "consumer",
        type = enums.CONSUMERS.TYPE.PROXY,
      }

      developer = bp.consumers:insert {
        username = "developer",
        email = "developer",
        type = enums.CONSUMERS.TYPE.DEVELOPER,
      }

      admin = bp.consumers:insert {
        username = "admin",
        type = enums.CONSUMERS.TYPE.ADMIN,
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("/consumers/:consumer/key-auth", function()
      describe("POST", function()
        after_each(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/admin/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin developers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/developer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for admin consumers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/consumer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("PUT", function()
        after_each(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/admin/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/developer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 204 for consumer user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/consumer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("GET", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/key-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developer/key-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumer user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/key-auth"
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("/developers/:developer/key-auth", function()
      describe("POST", function()
        after_each(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/admin/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for developer user", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/developer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)

        it("returns 404 for consumers user", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/consumer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PUT", function()
        after_each(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/admin/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for developer user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/developer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)

        it("returns 414 for consumer user", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/consumer/key-auth",
            body    = {
              key   = "1234"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)
      end)

      describe("GET", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/key-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developer user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/key-auth"
          })
          assert.res_status(200, res)
        end)

        it("returns 404 for consumer user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/key-auth"
          })
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/consumers/:consumer/key-auth/:id", function()
      before_each(function()
        dao:truncate_table("keyauth_credentials")

        admin_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = admin.id
        })

        developer_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = developer.id
        })

        consumer_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = consumer.id
        })
      end)

      describe("GET", function()
        it("returns 404 for admin user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/key-auth/" .. admin_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/key-auth/" .. admin_credential.key
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developer/key-auth/" .. developer_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developer/key-auth/" .. developer_credential.key
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumer user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/key-auth/" .. consumer_credential.id
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for consumer user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/key-auth/" .. consumer_credential.key
          })
          assert.res_status(200, res)
        end)
      end)

      describe("PATCH", function()
        it("returns 404 for admin user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/admin/key-auth/" .. admin_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/admin/key-auth/" .. admin_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/developer/key-auth/" .. developer_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/developer/key-auth/" .. developer_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumer user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/consumer/key-auth/" .. consumer_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for consumer user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/consumer/key-auth/" .. consumer_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)
      end)

      describe("DELETE", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/admin/key-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/developer/key-auth/" .. developer_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 204 for consumer user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/consumer/key-auth/" .. consumer_credential.id,
          })
          assert.res_status(204, res)
        end)
      end)
    end)

    describe("/developers/:developer/key-auth/:id", function()
      before_each(function()
        dao:truncate_table("keyauth_credentials")

        admin_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = admin.id
        })

        developer_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = developer.id
        })

        consumer_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = consumer.id
        })
      end)

      teardown(function()
        dao:truncate_table("keyauth_credentials")
      end)

      describe("GET", function()
        it("returns 404 for admin user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/key-auth/" .. admin_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/key-auth/" .. admin_credential.key
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developer user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/key-auth/" .. developer_credential.id
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developer user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/key-auth/" .. developer_credential.key
          })
          assert.res_status(200, res)
        end)

        it("returns 404 for consumer user by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/key-auth/" .. consumer_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumer user by key", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/key-auth/" .. consumer_credential.key
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it("returns 404 for admin user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/admin/key-auth/" .. admin_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/admin/key-auth/" .. admin_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for developer user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/developer/key-auth/" .. developer_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 201 for developer user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/developer/key-auth/" .. developer_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 404 for consumer user by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/consumer/key-auth/" .. consumer_credential.id,
            body    = {
              key   = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumer user by key", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/consumer/key-auth/" .. consumer_credential.key,
            body    = {
              key   = "4321UPD"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)
      end)

      describe("DELETE", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/admin/key-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 204 for developer user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/developer/key-auth/" .. developer_credential.id,
          })
          assert.res_status(204, res)
        end)

        it("returns 404 for developer user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/consumer/key-auth/" .. consumer_credential.id,
          })
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/key-auths", function()
      describe("GET", function()
        setup(function()
          assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id,
            key = '1',
          })

          assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id,
            key = '2',
          })

          assert(dao.keyauth_credentials:insert {
            consumer_id = admin.id,
            key = '3',
          })

          assert(dao.keyauth_credentials:insert {
            consumer_id = developer.id,
            key = '4',
          })

          assert(dao.keyauth_credentials:insert {
            consumer_id = developer.id,
            key = '5',
          })
        end)

        teardown(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("does not include admins and counts are off", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(4, #json.data)
          assert.equal(5, json.total)
        end)

        it("filters for an admin and counts are off", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths?consumer_id=" .. admin.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(0, #json.data)
          assert.equal(1, json.total)
        end)
      end)
    end)

    describe("/key-auths/:credential_key_or_id/consumer", function()
      describe("GET", function()

        setup(function()
          dao:truncate_table("keyauth_credentials")
          admin_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = admin.id,
          })

          consumer_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id,
          })

          developer_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = developer.id,
          })
        end)

        teardown(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admins by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. admin_credential.id .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admins by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. admin_credential.key .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. developer_credential.id .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. developer_credential.key .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumers by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. consumer_credential.id .. "/consumer"
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for consumers by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. consumer_credential.key .. "/consumer"
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("/key-auths/:credential_key_or_id/developer", function()
      describe("GET", function()

        setup(function()
          dao:truncate_table("keyauth_credentials")
          admin_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = admin.id,
          })

          consumer_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = consumer.id,
          })

          developer_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = developer.id,
          })
        end)

        teardown(function()
          dao:truncate_table("keyauth_credentials")
        end)

        it("returns 404 for admins by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. admin_credential.id .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admins by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. admin_credential.key .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developers by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. developer_credential.id .. "/developer"
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developers by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. developer_credential.key .. "/developer"
          })
          assert.res_status(200, res)
        end)

        it("returns 404 for consumers by id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. consumer_credential.id .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumers by key", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/" .. consumer_credential.key .. "/developer"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end
