local helpers = require "spec.helpers"
local cjson = require "cjson"
local ee_helpers = require "spec.ee_helpers"
local workspaces = require "kong.workspaces"
local enums      = require "kong.enterprise_edition.dao.enums"

local client
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
  return ee_helpers.register_rbac_resources(dao, workspace)
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API authentication on #" .. strategy, function()
    local dao
    local super_admin_rbac_user

    local function admin(client, assert, workspace, name, rbac_user_token, role, emailaddress)
      local headers = { ['Kong-Admin-Token'] = 'letmein'}
      local admin = post(client, "/" .. workspace .. "/admins",
                         { username = emailaddress,
                           email = emailaddress}, headers, 200)
      dao.consumers:update({status = enums.CONSUMERS.STATUS.APPROVED},
                           {id = admin.consumer.id})
      post(client, "/" .. workspace .. "/admins/".. admin.consumer.id
           .. "/roles", { roles = role }, headers, 201)
      return admin
    end

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("basic-auth authentication", function()
      local super_admin, read_me, proxy_consumer, another_one

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

        local workspace = workspaces.DEFAULT_WORKSPACE

        super_admin_rbac_user = setup_ws_defaults(dao, workspace)

        super_admin    = admin(client, assert, workspace, 'mars', 'let-me-in',
                               'super-admin','test@konghq.com')
        read_me        = admin(client, assert, workspace, 'gruce', 'let-me-in-now',
                               'read-only', 'test1@konghq.com')
        proxy_consumer = admin(client, assert, workspace, 'proxy-guy',
                               'let-me-in-now-plz', 'read-only', 'test2@konghq.com')

        assert(dao.basicauth_credentials:insert {
          username    = "i-am-mars",
          password    = "hunter1",
          consumer_id = super_admin.consumer.id,
        })

        assert(dao.basicauth_credentials:insert {
          username    = "i-am-gruce",
          password    = "hunter2",
          consumer_id = read_me.consumer.id,
        })

        assert(dao.basicauth_credentials:insert {
          username    = "i-am-proxy-guy",
          password    = "hunter3",
          consumer_id = proxy_consumer.consumer.id,
        })

        -- Another Workspace
        workspace = "another-one"
        setup_ws_defaults(dao, workspace)

        dao.rbac_roles:insert({ name = "another-one" })
        another_one = admin(client, assert, workspace, 'dj-khaled', 'another-one',
                            'another-one', 'test45@konghq.com')

        post(client, "/" .. workspace .. "/rbac/roles/another-one/endpoints", {
          workspace = "default",
          endpoint = "/consumers",
          actions = "read"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        post(client, "/" .. workspace .. "/rbac/roles/another-one/endpoints", {
          workspace = workspace,
          endpoint = "*",
          actions = "create,read,update,delete"
        }, { ['Kong-Admin-Token'] = 'letmein'}, 201)

        assert(dao.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer_id = another_one.consumer.id,
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

        it("returns 401 when unauthenticated and no token or credentials"
          .. " provided", function()
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
              ["Authorization"] = "Basic "
              .. ngx.encode_base64("i-am-mars:hunter1"),
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
              Authorization = "Basic "
              .. ngx.encode_base64("i-am-mars:hunter1"),
              ["Kong-Admin-User"] = read_me.rbac_user.name,
            }
          })

          assert.res_status(401, res)
        end)


        it("credentials in another workspace can access workspace data",
          function()
          local res = client:send {
            method = "GET",
            path = "/another-one/rbac/users",
            headers = {
              Authorization = "Basic "
              .. ngx.encode_base64("dj-khaled:another-one"),
              ["Kong-Admin-User"] = another_one.rbac_user.name,
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
              ["Kong-Admin-User"] = another_one.rbac_user.name,
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
              ["Kong-Admin-User"] = another_one.rbac_user.name,
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
              ['Kong-Admin-Token'] = another_one.rbac_user.user_token,
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
            path = "/another-one/rbac/users",
            headers = {
              ['Kong-Admin-Token'] = another_one.rbac_user.user_token,
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
              ['Kong-Admin-Token'] = another_one.rbac_user.user_token,
            }
          }

          assert.res_status(200, res)
        end)
      end)
    end)

    describe("key-auth authentication", function()
      local super_admin, read_me, proxy_consumer

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

        -- Default workspace
        local workspace = "default"

        super_admin    = admin(client, assert, workspace, 'mars', 'let-me-in', 'super-admin',
                               'test10@konghq.com')
        read_me        = admin(client, assert, workspace, 'gruce', 'let-me-in-now', 'read-only',
                               'test12@konghq.com')
        proxy_consumer = admin(client, assert, workspace, 'proxy-guy', 'let-me-in-now-plz',
                               'read-only', 'test14@konghq.com')

        assert(dao.keyauth_credentials:insert {
          key    = "hunter1",
          consumer_id = super_admin.consumer.id,
        })

        assert(dao.keyauth_credentials:insert {
          key    = "hunter2",
          consumer_id = read_me.consumer.id,
        })

        assert(dao.keyauth_credentials:insert {
          key    = "hunter3",
          consumer_id = proxy_consumer.consumer.id,
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
              ["Kong-Admin-User"] = read_me.rbac_user.name,
            }
          })

          assert.res_status(401, res)
        end)
      end)
    end)
  end)
end
