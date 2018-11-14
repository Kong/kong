local helpers = require "spec.helpers"
local cjson = require "cjson"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local enums = require "kong.enterprise_edition.dao.enums"
local admins = require "kong.enterprise_edition.admins_helpers"
local workspaces = require "kong.workspaces"
local ee_helpers = require "spec.ee_helpers"


describe("Admin API - ee-specific Kong routes", function()
  dao_helpers.for_each_dao(function(kong_conf)
    describe("/userinfo with db " .. kong_conf.database, function()

      local strategy = kong_conf.database
      local client
      local dao
      local bp

      after_each(function()
        helpers.stop_kong()
      end)

      teardown(function()
        -- this is just truncating tables, a side effect
        helpers.get_db_utils(strategy)
      end)

      it("return 404 on user info when admin_auth is off", function()
        helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
        }))

        client = assert(helpers.admin_client())

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
        })
        assert.res_status(404, res)
      end)

      it("returns 403 with admin_auth = on, invalid credentials", function()
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = 'basic-auth',
          enforce_rbac = 'on',
        }))

        client = assert(helpers.admin_client())

        bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          ["Authorization"] = "Basic " .. ngx.encode_base64("iam:invalid"),
        })

        assert.res_status(401, res)
      end)

      it("returns user info of admin consumer with rbac", function()
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        local _, super_role = ee_helpers.register_rbac_resources(dao)

        client = assert(helpers.admin_client())

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        local user = dao.rbac_users:insert {
          name = "hawk",
          user_token = "tawken",
          enabled = true,
        }

        -- make hawk super
        assert(dao.rbac_user_roles:insert({
          user_id = user.id,
          role_id = super_role.role_id,
        }))

        assert(dao.consumers_rbac_users_map:insert {
          consumer_id = consumer.id,
          user_id = user.id
        })

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
            ["Kong-Admin-User"] = "hawk",
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        local user_workspaces = json.workspaces
        json.workspaces = nil

        local expected = {
          consumer = consumer,
          rbac_user = user,
          permissions = {
            endpoints = {
              ["*"] = {
                ["*"] = {
                  actions = { "delete", "create", "update", "read", },
                  negative = false,
                }
              }
            },
            entities = {
              ["*"] = {
                actions = { "delete", "create", "update", "read", },
                negative = false,
              },
            },
          },
        }

        assert.same(expected, json)
        assert.equal(1, #user_workspaces)
        assert.equal(workspaces.DEFAULT_WORKSPACE, user_workspaces[1].name)

        -- Now send the same request, but with just the rbac token
        -- and make sure the responses are equivalent
        res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Kong-Admin-Token"] = "tawken",
          }
        })

        res = assert.res_status(200, res)
        local json2 = cjson.decode(res)
        local user_workspaces2 = json2.workspaces
        json2.workspaces = nil

        assert.same(json2, json)
        assert.same(user_workspaces2, user_workspaces)
      end)

      it("is whitelisted and supports legacy rbac_user.name", function()
        local _
        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        client = assert(helpers.admin_client())

        local user = dao.rbac_users:insert {
          name = "user-hawk",
          user_token = "tawken",
          enabled = true,
        }

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.ADMIN,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = consumer.username,
          password    = "kong",
          consumer_id = consumer.id,
        })

        assert(dao.consumers_rbac_users_map:insert {
          consumer_id = consumer.id,
          user_id = user.id
        })

        -- rbac_user.name is "user-hawk", can look up by consumer.username "hawk"
        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
            ["Kong-Admin-User"] = consumer.username,
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        assert.same(consumer, json.consumer)
        assert.same(user, json.rbac_user)
      end)

      it("returns 404 on user info when consumer is not mapped to rbac user, ", function()
        local bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "on",
        }))

        client = assert(helpers.proxy_client())

        local consumer = bp.consumers:insert {
          username = "hawk",
          type = enums.CONSUMERS.TYPE.PROXY,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        assert(dao.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer_id = consumer.id,
        })

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
            ["Kong-Admin-User"] = "hawk",
          }
        })

        assert.res_status(404, res)
      end)

      it("returns user info of admin consumer outside default workspace", function()
        local _

        bp, _, dao = helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both"
        }))

        client = assert(helpers.admin_client())

        -- populate a new workspace with an admin
        ee_helpers.register_rbac_resources(dao)
        local ws_name = "test-ws"
        local ws, err = dao.workspaces:insert({ name = ws_name, }, { quiet = true })
        if err then
          ws = dao.workspaces:find_all({ name = ws_name })[1]
        end
        ngx.ctx.workspaces = { ws }

        -- create the non-default admin
        local admin = ee_helpers.create_admin("test42@konghq.com", "dj-khaled",
                                              enums.CONSUMERS.STATUS.APPROVED,
                                              bp, dao)
        local rbac_user = admin.rbac_user
        admin.rbac_user = nil
        admins.link_to_workspace(admin, dao, ws_name)

        dao.rbac_roles:insert({ name = "another-one" })
        ee_helpers.post(client, "/" .. ws_name .. "/rbac/roles/another-one/endpoints", {
          workspace = "default",
          endpoint = "*",
          actions = "read"
        }, { ['Kong-Admin-Token'] = 'letmein'})

        ee_helpers.post(client, "/" .. ws_name .. "/admins/".. admin.id .. "/roles",
             { roles = "another-one" }, { ["Kong-Admin-Token"] = "letmein" }, 201)

        assert(dao.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer_id = admin.id,
        })

        -- Make sure non-default admin can still request /userinfo
        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("dj-khaled:another-one"),
            ["Kong-Admin-User"] = "test42@konghq.com",
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        local user_workspaces = json.workspaces
        json.workspaces = nil

        local expected = {
          consumer = admin,
          rbac_user = rbac_user,
          permissions = {
            endpoints = {
              ["default"] = {
                ["*"] = {
                  actions = { "read", },
                  negative = false,
                },
              },
            },
            entities = {}
          },
        }

        assert.same(expected, json)
        assert.equal(1, #user_workspaces)
        assert.equal("test-ws", user_workspaces[1].name)

        -- Now send the same request, but with just the rbac token
        -- and make sure the responses are equivalent
        res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Kong-Admin-Token"] = rbac_user.user_token,
          }
        })

        res = assert.res_status(200, res)
        local json2 = cjson.decode(res)
        local user_workspaces2 = json2.workspaces
        json2.workspaces = nil

        assert.same(json2, json)
        assert.same(user_workspaces2, user_workspaces)
      end)
    end)
  end)
end)
