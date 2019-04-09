local cjson   = require "cjson"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy() do
  pending("Pending on feature flags - Plugin (EE logic): basic-auth (API) [#" .. strategy .. "]", function()
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
        database = strategy,
      }))

      admin_client = helpers.admin_client()

    end)

    teardown(function()
      if admin_client then admin_client:close() end
      helpers.stop_kong()
    end)

    describe("/consumers/:consumer/basic-auth/", function()
      describe("POST", function()

        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/admin/basic-auth",
            body    = {
              username = "admin",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/developer/basic-auth",
            body    = {
              username = "admin",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res) 
        end)

        it("returns 200 for consumers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/consumers/consumer/basic-auth",
            body    = {
              username = "admin",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("PUT", function()
        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/admin/basic-auth",
            body    = {
              username = "admin2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/developer/basic-auth",
            body    = {
              username = "developer2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumers", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/consumers/consumer/basic-auth",
            body    = {
              username = "consumer2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("GET", function()
        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/basic-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developers/basic-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumers", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/basic-auth"
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("/developers/:developer/basic-auth/", function()

      teardown(function()
        dao:truncate_table("basicauth_credentials")
      end)

      describe("POST", function()
        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/admin/basic-auth",
            body    = {
              username = "admin2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/consumer/basic-auth",
            body    = {
              username = "consumer2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for developers", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/developers/developer/basic-auth",
            body    = {
              username = "developer2",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("PUT", function()
        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/admin/basic-auth",
            body    = {
              username = "admin",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumers", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/consumer/basic-auth",
            body    = {
              username = "consumer",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 201 for developers", function()
          local res = assert(admin_client:send {
            method  = "PUT",
            path    = "/developers/developer/basic-auth",
            body    = {
              username = "developer",
              password = "kong"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)

      describe("GET", function()
        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/basic-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumers", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/basic-auth"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developers", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/basic-auth"
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("/consumers/:consumer/basic-auth/:id", function()

      before_each(function()
        dao:truncate_table("basicauth_credentials")

        admin_credential = assert(dao.basicauth_credentials:insert {
          username = "admin1",
          password = "kong",
          consumer_id = admin.id
        })
        
        developer_credential = assert(dao.basicauth_credentials:insert {
          username = "developer1",
          password = "kong",
          consumer_id = developer.id
        })

        consumer_credential = assert(dao.basicauth_credentials:insert {
          username = "consumer1",
          password = "kong",
          consumer_id = consumer.id
        })
      end)

      teardown(function()
        dao:truncate_table("basicauth_credentials")
      end)

      describe("GET", function()
        it("returns 404 for admin by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.username
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developer/basic-auth/" .. developer_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/developer/basic-auth/" .. developer_credential.username
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumer by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/basic-auth/" .. consumer_credential.id
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for consumer by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/consumer/basic-auth/" .. consumer_credential.username
          })
          assert.res_status(200, res)
        end)
      end)

      describe("PATCH", function()
        it("returns 404 for admins by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admins by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/developer/basic-auth/" .. developer_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/developer/basic-auth/" .. developer_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developers by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/consumer/basic-auth/" .. consumer_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developers by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/consumers/consumer/basic-auth/" .. consumer_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)
      end)

      describe("DELETE", function()
        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/developer/basic-auth/" .. developer_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumers", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/consumer/basic-auth/" .. consumer_credential.id,
          })
          assert.res_status(204, res)
        end)
      end)
    end)

    describe("/developers/:developer/basic-auth/:id", function()

      before_each(function()
        dao:truncate_table("basicauth_credentials")

        admin_credential = assert(dao.basicauth_credentials:insert {
          username = "admin1",
          password = "kong",
          consumer_id = admin.id
        })
        
        developer_credential = assert(dao.basicauth_credentials:insert {
          username = "developer1",
          password = "kong",
          consumer_id = developer.id
        })

        consumer_credential = assert(dao.basicauth_credentials:insert {
          username = "consumer1",
          password = "kong",
          consumer_id = consumer.id
        })
      end)

      teardown(function()
        dao:truncate_table("basicauth_credentials")
      end)

      describe("GET", function()

        it("returns 404 for admin by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/basic-auth/" .. admin_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/admin/basic-auth/" .. admin_credential.username
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumer by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/basic-auth/" .. consumer_credential.id
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumer by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/consumer/basic-auth/" .. consumer_credential.username
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developer by id", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/basic-auth/" .. developer_credential.id
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developer by username", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/developers/developer/basic-auth/" .. developer_credential.username
          })
          assert.res_status(200, res)
        end)
      end)

      describe("PATCH", function()

        it("returns 404 for admins by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/admin/basic-auth/" .. admin_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admins by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/admin/basic-auth/" .. admin_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/consumer/basic-auth/" .. consumer_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/consumer/basic-auth/" .. consumer_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developers by id", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/developer/basic-auth/" .. developer_credential.id,
            body    = {
              password = "4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developers by username", function()
          local res = assert(admin_client:send {
            method  = "PATCH",
            path    = "/developers/developer/basic-auth/" .. developer_credential.username,
            body    = {
              password = "upd4321"
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)
        end)
      end)

      describe("DELETE", function()
        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/admin/basic-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developers", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/consumer/basic-auth/" .. consumer_credential.id,
          })
          assert.res_status(404, res)
        end)

        it("returns 204 for developers", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/developers/developer/basic-auth/" .. developer_credential.id,
          })
          assert.res_status(204, res)
        end)
      end)
    end)

    describe("/basic-auths", function()
      describe("GET", function()
        setup(function()
          assert(dao.basicauth_credentials:insert {
            consumer_id = consumer.id,
            username = 'consumer1',
            password = '1',
          })

          assert(dao.basicauth_credentials:insert {
            consumer_id = admin.id,
            username = 'admin1',
            password = '2',
          })
        end)

        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("filters for an admin and counts are off", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths?consumer_id=" .. admin.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(0, #json.data)
          assert.equal(1, json.total)
        end)
      end)
    end)

    describe("/basic-auths/:credential_username_or_id/consumer", function()
      describe("GET", function()

        setup(function()
          dao:truncate_table("basicauth_credentials")
          admin_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = admin.id,
                                      username = "admin" })

          consumer_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = consumer.id,
                                      username = "consumer" })

          developer_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = developer.id,
                                      username = "developer" })
        end)

        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admin from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. admin_credential.id .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. admin_credential.username .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. developer_credential.id .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for developer from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. developer_credential.username .. "/consumer"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for consumer from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. consumer_credential.id .. "/consumer"
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for consumer from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. consumer_credential.username .. "/consumer"
          })
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("/basic-auths/:developer_username_or_id/developer", function()
      describe("GET", function()

        setup(function()
          dao:truncate_table("basicauth_credentials")
          admin_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = admin.id,
                                      username = "admin" })

          consumer_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = consumer.id,
                                      username = "consumer" })

          developer_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = developer.id,
                                      username = "developer" })
        end)

        teardown(function()
          dao:truncate_table("basicauth_credentials")
        end)

        it("returns 404 for admin from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. admin_credential.id .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for admin from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. admin_credential.username .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 200 for developer from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. developer_credential.id .. "/developer"
          })
          assert.res_status(200, res)
        end)

        it("returns 200 for developer from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. developer_credential.username .. "/developer"
          })
          assert.res_status(200, res)
        end)

        it("returns 404 for consumer from a basic-auth id", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. consumer_credential.id .. "/developer"
          })
          assert.res_status(404, res)
        end)

        it("returns 404 for consumer from a basic-auth username", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/" .. consumer_credential.username .. "/developer"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end
