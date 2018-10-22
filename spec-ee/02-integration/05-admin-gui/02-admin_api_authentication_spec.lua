local helpers = require "spec.helpers"
local cjson = require "cjson"
local ee_helpers = require "spec.ee_helpers"
local workspaces = require "kong.workspaces"
local enums      = require "kong.enterprise_edition.dao.enums"
local admins = require "kong.enterprise_edition.admins_helpers"

local client
local bp, dao
local post = ee_helpers.post


local function setup_ws_defaults(dao, workspace)
  if not workspace then
    workspace = workspaces.DEFAULT_WORKSPACE
  end

  -- setup workspace and register rbac default roles
  local ws, err = dao.workspaces:insert({
      name = workspace,
  }, { quiet = true })

  if err then
    ws = dao.workspaces:find_all({ name = workspace })[1]
  end

  ngx.ctx.workspaces = { ws }
  ee_helpers.register_token_statuses(dao)
  helpers.register_consumer_relations(dao)

  -- create a record we can use to test inter-workspace calls
  assert(dao.consumers:insert({
    username = workspace .. "-joe"
  }))

  return ee_helpers.register_rbac_resources(dao, workspace)
end


local function admin(client, workspace, name, role, email)
  local admin = ee_helpers.create_admin(email,
                                        name,
                                        enums.CONSUMERS.STATUS.APPROVED,
                                        bp,
                                        dao)

  admins.link_to_workspace(admin, dao, workspace)

  post(client, "/" .. workspace .. "/admins/".. admin.id .. "/roles",
       { roles = role }, { ["Kong-Admin-Token"] = "letmein" }, 201)

  return admin
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API authentication on #" .. strategy, function()
    local super_admin_rbac_user

    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("basic-auth authentication", function()
      local super_admin, read_only_admin, test_admin

      setup(function()
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

        local ws_name = workspaces.DEFAULT_WORKSPACE

        super_admin_rbac_user = setup_ws_defaults(dao, ws_name)

        super_admin    = admin(client, ws_name, 'mars',
                               'super-admin','test@konghq.com')
        read_only_admin = admin(client, ws_name, 'gruce',
                               'read-only', 'test1@konghq.com')

        assert(dao.basicauth_credentials:insert {
          username    = super_admin.username,
          password    = "hunter1",
          consumer_id = super_admin.id,
        })

        assert(dao.basicauth_credentials:insert {
          username    = read_only_admin.username,
          password    = "hunter2",
          consumer_id = read_only_admin.id,
        })

        -- populate another workspace
        ws_name = "test-ws"
        setup_ws_defaults(dao, ws_name)

        dao.rbac_roles:insert({ name = "another-one" })
        test_admin = admin(client, ws_name, 'dj-khaled',
                            'another-one', 'test45@konghq.com')

        post(client, "/" .. ws_name .. "/rbac/roles/another-one/endpoints", {
          workspace = "default",
          endpoint = "/consumers",
          actions = "read"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        post(client, "/" .. ws_name .. "/rbac/roles/another-one/endpoints", {
          workspace = ws_name,
          endpoint = "*",
          actions = "create,read,update,delete"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        assert(dao.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer_id = test_admin.id,
        })
      end)

      teardown(function()
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
              ['Kong-Admin-Token'] = super_admin_rbac_user.user_token,
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
              ["Kong-Admin-User"] = super_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = super_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = read_only_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = test_admin.rbac_user.name,
            }
          }

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, #json.data)
        end)

        it("rbac token in another workspace can access data across workspaces",
          function()
          local res = client:send {
            method = "GET",
            path = "/consumers",
            headers = {
              Authorization = "Basic "
              .. ngx.encode_base64("dj-khaled:another-one"),
              ["Kong-Admin-User"] = test_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = test_admin.rbac_user.name,
            }
          }

          local body = assert.res_status(403, res)
          local json = cjson.decode(body)

          assert.truthy(string.match(json.message, "you do not have permissions"
                        .." to read"))
        end)

        it("rbac token in another workspace can NOT access workspace data not"
          .. " permissioned for", function()
          local res = client:send {
            method = "GET",
            path = "/plugins",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.user_token,
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
              ['Kong-Admin-Token'] = test_admin.rbac_user.user_token,
            }
          }
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, #json.data)
        end)

        it("rbac token in another workspace can access data across workspaces",
          function()
          local res = client:send {
            method = "GET",
            path = "/consumers",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.user_token,
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
        dao:truncate_tables()

        assert(helpers.start_kong({
          database   = strategy,
          admin_gui_auth = "key-auth",
          enforce_rbac = "on",
          rbac_auth_header = 'Kong-Admin-Token',
        }))

        client = assert(helpers.admin_client())

        super_admin_rbac_user = setup_ws_defaults(dao)

        local ws_name = "default"

        super_admin = admin(client, ws_name, 'mars', 'super-admin',
                               'test10@konghq.com')
        read_only_admin = admin(client, ws_name, 'gruce', 'read-only',
                               'test12@konghq.com')

        assert(dao.keyauth_credentials:insert {
          key    = "hunter1",
          consumer_id = super_admin.id,
        })

        assert(dao.keyauth_credentials:insert {
          key    = "hunter2",
          consumer_id = read_only_admin.id,
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
              ["Kong-Admin-User"] = super_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = super_admin.rbac_user.name,
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
              ["Kong-Admin-User"] = read_only_admin.rbac_user.name,
            }
          })

          assert.res_status(401, res)
        end)
      end)
    end)
  end)
end
