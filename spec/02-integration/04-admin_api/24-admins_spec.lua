local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local enums      = require "kong.enterprise_edition.dao.enums"
local utils      = require "kong.tools.utils"
local ee_helpers = require "spec.ee_helpers"


for _, strategy in helpers.each_strategy() do
  describe("Admin API - Admins", function()
    local client
    local dao
    local bp
    local admin, rbac_user, proxy_consumers
    local another_ws

    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
      }))

      another_ws = assert(dao.workspaces:insert({
        name = "another-one",
      }))

      ee_helpers.register_rbac_resources(dao)

      assert(bp.consumers:insert {
        username = "admin-1",
        custom_id = "admin-1",
        email = "admin-1@test.com",
        type = enums.CONSUMERS.TYPE.ADMIN
      })

      for i = 2, 5 do
        assert(bp.consumers:insert {
          username = "admin-" .. i,
          custom_id = "admin-" .. i,
          type = enums.CONSUMERS.TYPE.ADMIN
        })
      end

      for i = 1, 3 do
        assert(bp.consumers:insert {
          username = "developer-" .. i,
          custom_id = "developer-" .. i,
          type = enums.CONSUMERS.TYPE.DEVELOPER
        })

        proxy_consumers = assert(bp.consumers:insert {
          username = "consumer-" .. i,
          custom_id = "consumer-" .. i,
          type = enums.CONSUMERS.TYPE.PROXY
        })
      end

      assert(dao.rbac_users:insert({
        name = "user-test-test",
        user_token = utils.uuid(),
        enabled = true,
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("/admins", function()
      describe("GET", function ()

        it("retrieves list of admins only", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
            },
          })

          res = assert.res_status(200, res)
          local json = cjson.decode(res)
          assert.equal(5, #json.data)
        end)

      end)

      describe("POST", function ()
        it("creates an admin", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              custom_id = "cooper",
              username  = "dale",
            },
          })
          res = assert.res_status(200, res)
          local json = cjson.decode(res)

          admin = json.consumer
          rbac_user = json.rbac_user

          assert.equal("dale", json.consumer.username)
          assert.equal("cooper", json.consumer.custom_id)
          assert.equal(enums.CONSUMERS.TYPE.ADMIN, json.consumer.type)
          assert.equal(enums.CONSUMERS.STATUS.APPROVED, json.consumer.status)
          assert.truthy(utils.is_valid_uuid(json.rbac_user.user_token))
          assert.equal("user-dale-cooper", json.rbac_user.name)
        end)

        it("uses the admins_helpers validator", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/" .. another_ws.name .. "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              custom_id = "admin-1",
              username  = "i-am-unique",
            },
          })
          assert.res_status(409, res)
        end)
      end)
    end)

    describe("/admins/:admin_id", function()
      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/" .. admin.id,
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          admin.rbac_user = rbac_user
          assert.same(admin, json)
        end)

        it("retrieves by username", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/" .. admin.username,
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(admin, json)
        end)

        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/admins/not-an-admin",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it("updates by id", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/" .. admin.id,
              body = {
                username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(admin.id, json.id)

            local in_db = assert(bp.consumers:find {id = admin.id})
            assert.same(json, in_db)
          end
        end)

        it("updates by username", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/" .. admin.username,
              body = {
                username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(admin.id, json.id)

            local in_db = assert(bp.consumers:find {id = admin.id})
            assert.same(json, in_db)
          end
        end)

        it("returns 404 if not found", function()
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/not-an-admin",
              body = {
               username = "alice"
              },
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end
        end)
      end)

      describe("DELETE", function()
        local admin_id, expected

        before_each(function()
          dao:truncate_table('rbac_users')
          dao:truncate_table('rbac_roles')
          dao:truncate_table('consumers')
          dao:truncate_table('consumers_rbac_users_map')

          local res = assert(client:send {
            method = "POST",
            path  = "/admins",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              username = "gruce",
            },
          })

          assert.res_status(200, res)

          admin_id = dao.db:query("select * from consumers_rbac_users_map")[1].consumer_id
        end)

        it("deletes by id", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/" .. admin_id,
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)

          if dao.db_type == "postgres" then
            expected = {}
          else
            expected = {
              meta = {
                has_more_pages = false
              },
              type = "ROWS"
            }
          end

          assert.same(dao.db:query("select * from consumers_rbac_users_map"), expected)
          assert.same(dao.db:query("select * from rbac_users"), expected)
          assert.same(dao.db:query("select * from consumers"), expected)
          assert.same(dao.db:query("select * from rbac_roles"), expected)
        end)

        it("deletes by username", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/gruce",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)

          if dao.db_type == "postgres" then
            expected = {}
          else
            expected = {
              meta = {
                has_more_pages = false
              },
              type = "ROWS"
            }
          end

          assert.same(dao.db:query("select * from consumers_rbac_users_map"), expected)
          assert.same(dao.db:query("select * from rbac_users"), expected)
          assert.same(dao.db:query("select * from consumers"), expected)
          assert.same(dao.db:query("select * from rbac_roles"), expected)
        end)

        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "DELETE",
            path   = "/admins/not-an-admin",
            headers = {
              ["Kong-Admin-Token"] = "letmein",
              ["Content-Type"]     = "application/json",
            },
          })
          assert.res_status(404, res)
        end)
      end)

      describe("/admins/:consumer_id/workspaces", function()
        describe("GET", function()
          it("retrieves workspaces", function()
            local res = assert(client:send {
              method = "POST",
              path = "/admins",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
              body  = {
                custom_id = "cooper",
                username  = "dale",
              },
            })

            local body = assert.res_status(200, res)
            admin = cjson.decode(body)

            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.consumer.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(1, #json)
            assert.equal("default", json[1].name)
          end)

          it("returns multiple workspaces admin belongs to", function()
            local res = assert(client:send {
              method = "POST",
              path = "/workspaces/" .. another_ws.name .. "/entities",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
              body  = {
                entities = admin.consumer.id .. "," .. admin.rbac_user.id
              },
            })
            assert.res_status(201, res)

            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.consumer.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            local names = { json[1].name, json[2].name }
            assert.equal(2, #json)
            assert.contains("default", names)
            assert.contains(another_ws.name, names)
          end)

          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. admin.rbac_user.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end)

          it("returns 404 if consumer is not of type admin", function()
            local res = assert(client:send {
              method = "GET",
              path = "/admins/" .. proxy_consumers.id .. "/workspaces",
              headers = {
                ["Kong-Admin-Token"] = "letmein",
                ["Content-Type"]     = "application/json",
              },
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end
