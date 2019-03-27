local helpers = require "spec.helpers"
local cjson = require "cjson"
local ee_helpers = require "spec-ee.helpers"
local workspaces = require "kong.workspaces"
local utils = require "kong.tools.utils"

local client
local db, dao
local post = ee_helpers.post

local function truncate_tables(db)
  db:truncate("workspace_entities")
  db:truncate("consumers")
  db:truncate("rbac_user_roles")
  db:truncate("rbac_roles")
  db:truncate("rbac_users")
  db:truncate("admins")
end

local function setup_ws_defaults(dao, db, workspace)
  if not workspace then
    workspace = workspaces.DEFAULT_WORKSPACE
  end

  -- setup workspace and register rbac default roles
  local ws, err = db.workspaces:insert({
      name = workspace,
  }, { quiet = true })

  if err then
    ws = db.workspaces:select_by_name(workspace)
  end

  ngx.ctx.workspaces = { ws }
  helpers.register_consumer_relations(dao)

  -- create a record we can use to test inter-workspace calls
  assert(db.consumers:insert({ username = workspace .. "-joe" }))

  ee_helpers.register_rbac_resources(db, workspace)

  return ws
end


local function admin(db, workspace, name, role, email)
  return workspaces.run_with_ws_scope({workspace}, function ()
    local admin = db.admins:insert({
      username = name,
      email = email,
      status = 4, -- TODO remove once admins are auto-tagged as invited
    })

    local role = db.rbac_roles:select_by_name(role)
    db.rbac_user_roles:insert({
      user = { id = admin.rbac_user.id },
      role = { id = role.id }
    })

    local raw_user_token = utils.uuid()
    assert(db.rbac_users:update({id = admin.rbac_user.id}, {
      user_token = raw_user_token
    }))
    admin.rbac_user.raw_user_token = raw_user_token

    return admin
  end)
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API authentication on #" .. strategy, function()
    lazy_setup(function()
      _, db, dao = helpers.get_db_utils(strategy)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("basic-auth authentication", function()
      local super_admin, read_only_admin, test_admin

      lazy_setup(function()
        helpers.stop_kong()

        assert(helpers.start_kong({
          database   = strategy,
          admin_gui_auth = "basic-auth",
          enforce_rbac = "on",
          admin_gui_auth_config = "{ \"hide_credentials\": true }",
          rbac_auth_header = 'Kong-Admin-Token',
          smtp_mock = true,
        }))

        client = assert(helpers.admin_client())

        local ws = setup_ws_defaults(dao, db, workspaces.DEFAULT_WORKSPACE)
        super_admin = admin(db, ws, 'mars', 'super-admin','test@konghq.com')
        read_only_admin = admin(db, ws, 'gruce', 'read-only', 'test1@konghq.com')

        assert(db.basicauth_credentials:insert {
          username    = super_admin.username,
          password    = "hunter1",
          consumer = {
            id = super_admin.consumer.id,
          },
        })

        assert(db.basicauth_credentials:insert {
          username    = read_only_admin.username,
          password    = "hunter2",
          consumer = {
            id = read_only_admin.consumer.id,
          },
        })

        -- populate another workspace
        ws = setup_ws_defaults(dao, db, "test-ws")

        db.rbac_roles:insert({ name = "another-one" })
        test_admin = admin(db, ws, 'dj-khaled',
                            'another-one', 'test45@konghq.com')

        post(client, "/" .. ws.name .. "/rbac/roles/another-one/endpoints", {
          workspace = "default",
          endpoint = "/consumers",
          actions = "read"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        post(client, "/" .. ws.name .. "/rbac/roles/another-one/endpoints", {
          workspace = ws.name,
          endpoint = "*",
          actions = "create,read,update,delete"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        assert(db.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer = {
            id = test_admin.consumer.id,
          },
        })
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end
      end)

      describe("GET", function()
        it("internal proxy no longer exists when gui_auth is enabled",
        function()
          local res = assert(client:send {
            method = "GET",
            path = "/_kong/admin",
            headers = {
              ['Kong-Admin-Token'] = "letmein",
            },
          })

          assert.res_status(404, res)
        end)

        it("returns 401 when no token or credentials provided", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
          })

          assert.res_status(401, res)
        end)

        it("returns 200 when only rbac token is present", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ['Kong-Admin-Token'] = "letmein",
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("Welcome to kong", json.tagline)
        end)

        it("returns 200 when authenticated with credentials", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Authorization"] = "Basic " .. ngx.encode_base64(super_admin.username .. ":hunter1"),
              ["Kong-Admin-User"] = super_admin.username,
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("Welcome to kong", json.tagline)
        end)

        it("returns 401 when user token is invalid", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Authorization"] = "Basic "
              .. ngx.encode_base64("i-am-mars:but-mypassword-is-wrong"),
              ["Kong-Admin-User"] = 'sup-dawg',
            }
          })

          assert.res_status(401, res)
        end)

        it("returns 403 when authenticated with invalid password", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Authorization"] = "Basic "
              .. ngx.encode_base64("i-am-mars:but-mypassword-is-wrong"),
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          assert.res_status(403, res)
        end)

        it("returns 401 when authenticated with mismatched user/credentials",
          function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              Authorization = "Basic " .. ngx.encode_base64(super_admin.username .. ":hunter1"),
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          })

          assert.res_status(401, res)
        end)


        it("credentials in another workspace can access workspace data", function()
          local res = client:send {
            method = "GET",
            path = "/test-ws/consumers",
            headers = {
              Authorization = "Basic " .. ngx.encode_base64("dj-khaled:another-one"),
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          -- TODO just count #json.data when admins are filtered out of consumers
          local count = 0
          for k, c in ipairs(json.data) do
            if c.type == 0 then
              count = count + 1
            end
          end

          assert.equal(1, count)
        end)

        it("rbac token in another workspace can access data across workspaces",
          function()
          local res = client:send {
            method = "GET",
            path = "/consumers",
            headers = {
              Authorization = "Basic "
              .. ngx.encode_base64("dj-khaled:another-one"),
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          assert.res_status(200, res)
        end)

        it("credentials in another workspace cannot access workspace data not"
          .. " permissioned for", function()
          local res = client:send {
            method = "GET",
            path = "/plugins",
            headers = {
              Authorization = "Basic "
              .. ngx.encode_base64("dj-khaled:another-one"),
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          local body = assert.res_status(403, res)
          local json = cjson.decode(body)

          assert.truthy(string.match(json.message, "you do not have permissions"
                        .." to read"))
        end)

        -- TODO: address using admin raw token once we can safely reset it/know it
        pending("rbac token in another workspace can NOT access workspace data not"
          .. " permissioned for", function()
          local res = client:send {
            method = "GET",
            path = "/plugins",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.raw_user_token,
            }
          }

          local body = assert.res_status(403, res)
          local json = cjson.decode(body)

          assert.truthy(string.match(json.message, "you do not have permissions"
                        .. " to read"))
        end)

        it("rbac token in another workspace can access workspace data",
          function()
          local res = client:send {
            method = "GET",
            path = "/test-ws/consumers",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.raw_user_token,
            }
          }
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          -- TODO just count #json.data when admins are filtered out of consumers
          local count = 0
          for k, c in ipairs(json.data) do
            if c.type == 0 then
              count = count + 1
            end
          end

          assert.equal(1, count)
        end)

        -- TODO: address using admin raw token once we can safely reset it/know it
        pending("rbac token in another workspace can access data across workspaces",
          function()
          local res = client:send {
            method = "GET",
            path = "/consumers",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.raw_user_token,
            }
          }

          assert.res_status(200, res)
        end)
      end)
    end)

    describe("key-auth authentication", function()
      local super_admin, read_only_admin

      setup(function()
        helpers.stop_kong()
        truncate_tables(db)

        assert(helpers.start_kong({
          database   = strategy,
          admin_gui_auth = "key-auth",
          enforce_rbac = "on",
          rbac_auth_header = 'Kong-Admin-Token',
        }))

        client = assert(helpers.admin_client())

        local ws = setup_ws_defaults(dao, db)

        super_admin = admin(db, ws, 'mars', 'super-admin',
                               'test10@konghq.com')
        read_only_admin = admin(db, ws, 'gruce', 'read-only',
                               'test12@konghq.com')

        assert(db.keyauth_credentials:insert {
          key    = "hunter1",
          consumer = {
            id = super_admin.consumer.id,
          },
        })

        assert(db.keyauth_credentials:insert {
          key    = "hunter2",
          consumer = {
            id = read_only_admin.consumer.id,
          },
        })
      end)

      teardown(function()
        if client then
          client:close()
        end
      end)

      describe("GET", function()
        it("returns 200 when authenticated with credentials", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              apikey = "hunter1",
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal("Welcome to kong", json.tagline)
        end)

        it("returns 403 when authenticated with invalid password", function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              apikey = "my-key-is-wrong",
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          assert.res_status(403, res)
        end)

        it("returns 401 when authenticated with mismatched user/credentials",
          function()
          local res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              apikey = "hunter1",
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          })

          assert.res_status(401, res)
        end)
      end)
    end)
  end)
end
