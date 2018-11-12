local cjson   = require "cjson"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy() do
  describe("Plugin (EE logic): basic-auth (API) [#" .. strategy .. "]", function()
    local admin
    local admin_client
    local dao

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

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
      setup(function()
        admin = dao.consumers:run_with_ws_scope(
                dao.workspaces:find_all({name = "default"}),
                dao.consumers.insert,
                {
                  username = "admin",
                  type =  enums.CONSUMERS.TYPE.ADMIN,
                })
        end)

      after_each(function()
        dao:truncate_table("basicauth_credentials")
      end)

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
      end)

      describe("PUT", function()
        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "PUT",
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
      end)

      describe("GET", function()
        setup(function()
          for i = 1, 3 do
            assert(dao.basicauth_credentials:insert {
              username    = "admin" .. i,
              password    = "kong",
              consumer_id = admin.id
            })
          end
        end)

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
      end)
    end)

    describe("/consumers/:consumer/basic-auth/:id", function()
      local admin_credential

      before_each(function()
        dao:truncate_table("basicauth_credentials")

        admin_credential = dao.basicauth_credentials:run_with_ws_scope(
                           dao.workspaces:find_all({name = "default"}),
                           dao.basicauth_credentials.insert, {
                           username = "admin",
                           password = "kong",
                           consumer_id = admin.id
                         })
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
      end)

      describe("DELETE", function()
        it("returns 404 for admins", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/admin/basic-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/basic-auths", function()
      local consumer2

      describe("GET", function()
        setup(function()
          dao:truncate_table("basicauth_credentials")

          consumer2 = assert(dao.consumers:insert {
            username = "bob-the-builder",
          })

          assert(dao.basicauth_credentials:insert {
            consumer_id = consumer2.id,
            username = consumer2.username,
          })

          assert(dao.basicauth_credentials:insert {
            consumer_id = admin.id,
            username = admin.username,
          })
        end)

        it("does not include admins and counts are off", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/basic-auths/"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(1, #json.data)
          assert.equal(2, json.total)
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
        local admin_credential

        setup(function()
          dao:truncate_table("basicauth_credentials")
          admin_credential = assert(dao.basicauth_credentials:insert {
                                      consumer_id = admin.id,
                                      username = "admin" })
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
      end)
    end)
  end)
end
