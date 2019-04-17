local helpers = require "spec.helpers"
local cjson = require "cjson"
local enums = require "kong.enterprise_edition.dao.enums"
local admins = require "kong.enterprise_edition.admins_helpers"
local workspaces = require "kong.workspaces"
local ee_helpers = require "spec-ee.helpers"
local rbac = require "kong.rbac"


local function admin(db, workspace, name, role, email)
  local ws, err = db.workspaces:select_by_name(workspace)
  assert.is_nil(err)
  assert.not_nil(ws)
  assert.same(workspace, ws.name)

  return workspaces.run_with_ws_scope({ws}, function ()
    local admin, err = db.admins:insert({
      username = name,
      email = email,
      status = 4, -- TODO remove once admins are auto-tagged as invited
    })
    assert.is_nil(err)

    local role = db.rbac_roles:select_by_name(role)
    assert.is_not_nil(role)
    assert(db.rbac_user_roles:insert({
      user = { id = admin.rbac_user.id },
      role = { id = role.id },
    }))

    return admin
  end)
end


describe("Admin API - ee-specific Kong routes", function()
  for _, strategy in helpers.each_strategy() do
    describe("/userinfo with db #" .. strategy, function()

      local strategy = strategy
      local client
      local db

      after_each(function()
        helpers.stop_kong()
        if client then
          client:close()
        end
      end)

      before_each(function()
        db = select(2, helpers.get_db_utils(strategy))
      end)

      lazy_teardown(function()
        -- this is just truncating tables, a side effect
        helpers.get_db_utils(strategy)
      end)

      it("return 404 on user info when admin_auth is off", function()
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
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = 'basic-auth',
          enforce_rbac = 'on',
        }))

        client = assert(helpers.admin_client())

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          ["Authorization"] = "Basic " .. ngx.encode_base64("iam:invalid"),
        })

        assert.res_status(401, res)
      end)

      it("returns user info of admin consumer with rbac", function()
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        ee_helpers.register_rbac_resources(db)

        client = assert(helpers.admin_client())

        local admin = admin(db, 'default', 'hawk', 'super-admin')

        assert(db.basicauth_credentials:insert {
          username    = "hawk",
          password    = "kong",
          consumer = {
            id = admin.consumer.id,
          },
        })

        local res = assert(client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
            ["Kong-Admin-User"] = admin.username,
          }
        })

        res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["cookie"] = res.headers['Set-Cookie'],
            ["Kong-Admin-User"] = "hawk",
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        local user_workspaces = json.workspaces
        json.workspaces = nil
        json.admin.updated_at = nil

        local admin_res = admins.transmogrify(admin)
        -- updated_at changes when user logs in and status switches to approved
        admin_res.updated_at = nil
        admin_res.status = enums.CONSUMERS.STATUS.APPROVED

        local expected = {
          admin = admin_res,
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

        --- TODO: add this back once we can know the rbac_user.token of admin
        --
        -- Now send the same request, but with just the rbac token
        -- and make sure the responses are equivalent
        -- res = assert(client:send {
        --   method = "GET",
        --   path = "/userinfo",
        --   headers = {
        --     ["Kong-Admin-Token"] = admin.rbac_user.raw_user_token,
        --   }
        -- })

        -- res = assert.res_status(200, res)
        -- local json2 = cjson.decode(res)
        -- local user_workspaces2 = json2.workspaces

        -- json2.workspaces = nil
        -- json2.admin.updated_at = nil

        -- assert.same(json2, json)
        -- assert.same(user_workspaces2, user_workspaces)
      end)

      it("/userinfo whitelisted - admin consumer success without needing /userinfo " ..
         "rbac endpoint permissions", function()
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both",
        }))

        ee_helpers.register_rbac_resources(db)
        client = assert(helpers.admin_client())


        -- create the non-default admin
        local role = db.rbac_roles:insert({ name = "not-much-role" })
        assert(db.rbac_role_endpoints:insert {
          role = { id = role.id },
          endpoint = "/snis", -- just one endpoint to some random entity
          workspace = "default",
          actions = rbac.actions_bitfields.read
        })

        local admin = admin(db, 'default', 'not-trustworthy', 'not-much-role')

        assert(db.basicauth_credentials:insert {
          username    = "not-trustworthy",
          password    = "12345", -- so secure :facepalm: !!!
          consumer = {
            id = admin.consumer.id,
          },
        })

        local res = assert(client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("not-trustworthy:12345"),
            ["Kong-Admin-User"] = admin.username,
          }
        })

        res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["cookie"] = res.headers['Set-Cookie'],
            ["Kong-Admin-User"] = "not-trustworthy",
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        assert.equal(1, #json.workspaces)
      end)


      it("returns 404 when rbac user is not mapped to an admin", function()
        db = select(2, helpers.get_db_utils(strategy))

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "on",
        }))

        client = assert(helpers.proxy_client())

        db.rbac_users:insert {
          name = "some-user",
          user_token = "billgatesletmeinnow",
        }

        local res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["Kong-Admin-Token"] = "billgatesletmeinnow",
          }
        })

        assert.res_status(404, res)
      end)

      it("returns user info of admin consumer outside default workspace", function()
        db = select(2, helpers.get_db_utils(strategy))

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "both"
        }))

        client = assert(helpers.admin_client())

        -- populate a new workspace with an admin
        ee_helpers.register_rbac_resources(db)
        local ws_name = "test-ws"
        local ws, err = db.workspaces:insert({ name = ws_name, }, { quiet = true })
        if err then
          ws = db.workspaces:select_by_name(ws_name)
        end
        ngx.ctx.workspaces = { ws }

        -- create the non-default admin
        local role = db.rbac_roles:insert({ name = "another-one" })
        local admin = admin(db, "test-ws", "dj-khaled", "another-one", "test42@konghq.com")
        admin.rbac_user = nil
        admin.status = enums.CONSUMERS.STATUS.APPROVED
        admin.updated_at = nil
        admins.link_to_workspace(admin, ws_name)

        assert(db.rbac_role_endpoints:insert {
          role = { id = role.id },
          endpoint = "*",
          workspace = "default",
          actions = rbac.actions_bitfields.read
        })

        assert(db.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer = {
            id = admin.consumer.id,
          },
        })

        local res = assert(client:send {
          method = "GET",
          path = "/auth",
          headers = {
            ["Authorization"] = "Basic " .. ngx.encode_base64("dj-khaled:another-one"),
            ["Kong-Admin-User"] = admin.username,
          }
        })

        -- Make sure non-default admin can still request /userinfo
        res = assert(client:send {
          method = "GET",
          path = "/userinfo",
          headers = {
            ["cookie"] = res.headers['Set-Cookie'],
            ["Kong-Admin-User"] = admin.username,
          }
        })

        res = assert.res_status(200, res)
        local json = cjson.decode(res)

        local user_workspaces = json.workspaces
        json.workspaces = nil
        json.admin.updated_at = nil

        local expected = {
          admin = admins.transmogrify(admin),
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

        -- TODO: add this back once we can know the rbac_user.token of admin
        -- insert.
        --
        -- Now send the same request, but with just the rbac token
        -- and make sure the responses are equivalent
        -- local rbac_user = admin.rbac_user
        -- local token = rbac_user.raw_user_token
        -- rbac_user.raw_user_token = nil
        -- res = assert(client:send {
        --   method = "GET",
        --   path = "/userinfo",
        --   headers = {
        --     ["Kong-Admin-Token"] = token,
        --   }
        -- })

        -- res = assert.res_status(200, res)
        -- local json2 = cjson.decode(res)
        -- local user_workspaces2 = json2.workspaces
        -- json2.workspaces = nil
        -- json2.admin.updated_at = nil

        -- assert.same(json2, json)
        -- assert.same(user_workspaces2, user_workspaces)
      end)
    end)
  end
end)
