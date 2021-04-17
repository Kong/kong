-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local enums = require "kong.enterprise_edition.dao.enums"
local admins = require "kong.enterprise_edition.admins_helpers"
local ee_helpers = require "spec-ee.helpers"
local rbac = require "kong.rbac"


local function insert_admin(db, workspace, name, role, email)
  local ws, err = db.workspaces:select_by_name(workspace)
  assert.is_nil(err)
  assert.not_nil(ws)
  assert.same(workspace, ws.name)

  local admin, err = db.admins:insert({
    username = name,
    email = email,
    status = 4, -- TODO remove once admins are auto-tagged as invited
  }, { workspace = ws.id })
  assert.is_nil(err)

  local role, err = db.rbac_roles:select_by_name(role, { workspace = ws.id })
  assert.is_not_nil(role, tostring(err))
  assert(db.rbac_user_roles:insert({
    user = { id = admin.rbac_user.id },
    role = { id = role.id },
  }))

  return admin
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API - ee-specific Kong routes /userinfo with db #" .. strategy, function()
    describe("default", function()
      local client
      local db

      after_each(function()
        helpers.stop_kong()
        if client then
          client:close()
        end
      end)

      lazy_setup(function()
        db = select(2, helpers.get_db_utils(strategy))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
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
          admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
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

      it("/userinfo whitelisted - admin consumer success without needing /userinfo " ..
        "rbac endpoint permissions", function()
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
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

        local admin = insert_admin(db, 'default', 'not-trustworthy', 'not-much-role')

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
        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
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

        assert(helpers.start_kong({
          database = strategy,
          admin_gui_auth = "basic-auth",
          admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
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

        -- add a workspace and role to admin that admin is not "linked" in
        local ws1, err = db.workspaces:insert({ name = "test-ws-1", }, { quiet = true })
        if err then
          ws1 = db.workspaces:select_by_name("test-ws-1")
        end
        local role1 = db.rbac_roles:insert({ name = "hello" }, { workspace = ws1.id })
        assert(role1)

        ngx.ctx.workspace = ws.id

        -- create the non-default admin
        local role = db.rbac_roles:insert({ name = "another-one" })
        local admin = insert_admin(db, "test-ws", "dj-khaled", "another-one", "test42@konghq.com")

        -- add a role that rbac_user is not "linked" to
        db.rbac_user_roles:insert({
          user = { id = admin.rbac_user.id },
          role = { id = role1.id },
        })

        admin.rbac_user = nil
        admin.status = enums.CONSUMERS.STATUS.APPROVED
        admin.updated_at = nil

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

        assert.same(expected.admin, json.admin)
        assert.same(expected.permissions, json.permissions)

        -- includes workspace admin is not "linked" in
        assert.equal(2, #json.workspaces)
        assert.equal("test-ws", json.workspaces[1].name)
        assert.equal("test-ws-1", json.workspaces[2].name)
      end)
    end)
  end)

  describe('Admin API - ee-specific Kong routes user information #' .. strategy, function ()
    local client, db, admin1
    local session_config = {
      cookie_lifetime = 6000,
      cookie_renew = 5900,
      secret = "super-secret"
    }

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    lazy_setup(function ()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database = strategy,
        admin_gui_auth = "basic-auth",
        enforce_rbac = "both",
        admin_gui_session_conf = cjson.encode(session_config),
      }))

      ee_helpers.register_rbac_resources(db)

      client = assert(helpers.admin_client())

      admin1 = insert_admin(db, 'default', 'hawk', 'super-admin')

      assert(db.basicauth_credentials:insert {
        username    = "hawk",
        password    = "kong",
        consumer = {
          id = admin1.consumer.id,
        },
      })
    end)

    it("admin meta", function()
      local cookie = ee_helpers.get_admin_cookie_basic_auth(client, 'hawk', 'kong')
      local res = assert(client:send {
        method = "GET",
        path = "/userinfo",
        headers = {
          ["cookie"] = cookie,
          ["Kong-Admin-User"] = "hawk",
        }
      })

      res = assert.res_status(200, res)
      local json = cjson.decode(res)

      local admin_res = admins.transmogrify(admin1)
      -- updated_at changes when user logs in and status switches to approved
      admin_res.updated_at = nil
      admin_res.status = enums.CONSUMERS.STATUS.APPROVED

      assert.equal(admin_res.id, json.admin.id)
      assert.equal(admin_res.status, json.admin.status)
      assert.equal(admin_res.rbac_token_enabled, json.admin.rbac_token_enabled)
      assert.equal(admin_res.username, json.admin.username)
    end)

    it("rbac permissions", function()
      local cookie = ee_helpers.get_admin_cookie_basic_auth(client, 'hawk', 'kong')
      local res = assert(client:send {
        method = "GET",
        path = "/userinfo",
        headers = {
          ["cookie"] = cookie,
          ["Kong-Admin-User"] = "hawk",
        }
      })

      res = assert.res_status(200, res)
      local json = cjson.decode(res)

      local expected = {
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
      }

      assert.same(expected, json.permissions)
    end)

    it("workspaces", function()
      local cookie = ee_helpers.get_admin_cookie_basic_auth(client, 'hawk', 'kong')
      local res = assert(client:send {
        method = "GET",
        path = "/userinfo",
        headers = {
          ["cookie"] = cookie,
          ["Kong-Admin-User"] = "hawk",
        }
      })

      res = assert.res_status(200, res)
      local json = cjson.decode(res)

      assert.same(1, #json.workspaces)
      assert.equal("default", json.workspaces[1].name)
    end)

    it("session", function()
      local cookie = ee_helpers.get_admin_cookie_basic_auth(client, 'hawk', 'kong')
      local res = assert(client:send {
        method = "GET",
        path = "/userinfo",
        headers = {
          ["cookie"] = cookie,
          ["Kong-Admin-User"] = "hawk",
        }
      })

      res = assert.res_status(200, res)
      local json = cjson.decode(res)

      assert.same(session_config.cookie_renew, json.session.cookie.renew) -- fetches custom config
      assert.same(session_config.cookie_lifetime, json.session.cookie.lifetime)
      assert.same(10, json.session.cookie.discard) -- fetches default
    end)
  end)
end
