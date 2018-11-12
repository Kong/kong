local cjson   = require "cjson"
local helpers = require "spec.helpers"
local enums = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy() do
  describe("Plugin (EE logic): key-auth (API) [" .. strategy .. "]", function()
    local consumer
    local admin
    local admin_client
    local dao

    setup(function()
      local bp, _
      bp, _, dao = helpers.get_db_utils(strategy)

      consumer = bp.consumers:insert {
        username = "bob",
        type = enums.CONSUMERS.TYPE.PROXY,
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
      end)

      describe("GET", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/consumers/admin/key-auth"
          })
          assert.res_status(404, res)
        end)
      end)
    end)

    describe("/consumers/:consumer/key-auth/:id", function()
      local admin_credential

      before_each(function()
        dao:truncate_table("keyauth_credentials")

        admin_credential = assert(dao.keyauth_credentials:insert {
          consumer_id = admin.id
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
      end)

      describe("DELETE", function()
        it("returns 404 for admin user", function()
          local res = assert(admin_client:send {
            method  = "DELETE",
            path    = "/consumers/admin/key-auth/" .. admin_credential.id,
          })
          assert.res_status(404, res)
        end)
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

          consumer2 = assert(dao.consumers:insert {
            username = "bob-the-buidler"
          })

          for i = 1, 3 do
            assert(dao.keyauth_credentials:insert {
              consumer_id = consumer2.id
            })
          end

          assert(dao.keyauth_credentials:insert {
            consumer_id = admin.id
          })
        end)

        it("does not include admins and counts are off", function()
          local res = assert(admin_client:send {
            method = "GET",
            path = "/key-auths/",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.is_table(json.data)
          assert.equal(6, #json.data)
          assert.equal(7, json.total)
        end)

        it("filters key-auths for an admin and counts are off", function()
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
        local admin_credential

        setup(function()
          dao:truncate_table("keyauth_credentials")
          admin_credential = assert(dao.keyauth_credentials:insert {
            consumer_id = admin.id
          })
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
      end)
    end)
  end)
end
