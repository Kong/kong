local helpers = require "spec.helpers"
local cjson = require "cjson"
local ee_helpers = require "spec-ee.helpers"
local workspaces = require "kong.workspaces"
local secrets = require "kong.enterprise_edition.consumer_reset_secret_helpers"
local utils = require "kong.tools.utils"

local client
local db, dao
local post = ee_helpers.post
local get_admin_cookie_basic_auth = ee_helpers.get_admin_cookie_basic_auth

local function truncate_tables(db)
  db:truncate("workspace_entities")
  db:truncate("consumers")
  db:truncate("admins")
  db:truncate("rbac_role_endpoints")
  db:truncate("rbac_user_roles")
  db:truncate("rbac_roles")
  db:truncate("rbac_users")
  db:truncate("groups")
  db:truncate("login_attempts")
  db:truncate("basicauth_credentials")
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

  -- create a record we can use to test inter-workspace calls
  assert(db.services:insert({  host = workspace .. "-example.com", }))

  ee_helpers.register_rbac_resources(db, workspace)

  return ws
end


local function admin(db, workspace, name, role, email)
  return workspaces.run_with_ws_scope({workspace}, function ()
    local admin = assert(db.admins:insert({
      username = name,
      email = email,
      status = 4, -- TODO remove once admins are auto-tagged as invited
    }))

    if role then
      local role = db.rbac_roles:select_by_name(role)
      db.rbac_user_roles:insert({
        user = { id = admin.rbac_user.id },
        role = { id = role.id }
      })
    end

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
      _, db, dao = helpers.get_db_utils(strategy, {
        'services',
        'routes',
        'admins',
        'consumers',
        'plugins',
        'login_attempts'
      }, { "ldap-auth-advanced" })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if client then
        client:close()
      end
    end)

    describe("basic-auth authentication #test", function()
      local super_admin, read_only_admin, test_admin

      lazy_setup(function()
        truncate_tables(db)

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
          endpoint = "/services",
          actions = "read"
        }, { ['Kong-Admin-Token'] = 'letmein-' .. ws.name }, 201)

        post(client, "/" .. ws.name .. "/rbac/roles/another-one/endpoints", {
          workspace = ws.name,
          endpoint = "*",
          actions = "create,read,update,delete"
        }, { ['Kong-Admin-Token'] = 'letmein-' .. ws.name }, 201)

        assert(db.basicauth_credentials:insert {
          username    = "dj-khaled",
          password    = "another-one",
          consumer = {
            id = test_admin.consumer.id,
          },
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
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
              ['Kong-Admin-Token'] = 'letmein-' .. 'default',
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
              ['Kong-Admin-Token'] = 'letmein-' .. 'default',
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

        it("returns 401 when authenticated with invalid password", function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              ["Authorization"] = "Basic "
              .. ngx.encode_base64("i-am-mars:but-mypassword-is-wrong"),
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          assert.res_status(401, res)
        end)

        it("returns 401 when authenticated with mismatched user/credentials",
          function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              Authorization = "Basic " .. ngx.encode_base64(super_admin.username .. ":hunter1"),
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          })

          assert.res_status(401, res)
        end)


        it("credentials in another workspace can access workspace data", function()
          local cookie = get_admin_cookie_basic_auth(client, test_admin.username, 'another-one')
          local res = client:send {
            method = "GET",
            path = "/test-ws/services",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          assert.res_status(200, res)
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, #json.data)
        end)

        it("rbac token in another workspace can access data across workspaces",
          function()
          local cookie = get_admin_cookie_basic_auth(client, test_admin.username, 'another-one')
          local res = client:send {
            method = "GET",
            path = "/services",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          assert.res_status(200, res)
        end)

        it("credentials in another workspace cannot access workspace data not"
          .. " permissioned for", function()
          local cookie = get_admin_cookie_basic_auth(client, test_admin.username, 'another-one')
          local res = client:send {
            method = "GET",
            path = "/plugins",
            headers = {
              ["cookie"] = cookie,
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
            path = "/test-ws/services",
            headers = {
              ['Kong-Admin-Token'] = test_admin.rbac_user.raw_user_token,
            }
          }
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, #json.data)
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

      describe("GET", function()
        it("/auth returns 200 with credentials", function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              ["Authorization"] = "Basic " .. ngx.encode_base64(super_admin.username .. ":hunter1"),
              ["Kong-Admin-User"] = super_admin.username,
            }
          })
          assert.res_status(200, res)
        end)

        it("returns 401 when authenticated with invalid password", function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              ["Authorization"] = "Basic "
              .. ngx.encode_base64("i-am-mars:but-mypassword-is-wrong"),
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          assert.res_status(401, res)
        end)

        it("returns 401 when authenticated with mismatched user/credentials",
          function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              Authorization = "Basic " .. ngx.encode_base64(super_admin.username .. ":hunter1"),
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          })

          assert.res_status(401, res)
        end)


        it("credentials in another workspace can access workspace data", function()
          local cookie = get_admin_cookie_basic_auth(client, test_admin.username, 'another-one')

          local res = client:send {
            method = "GET",
            path = "/test-ws/services",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = test_admin.username,
            }
          }

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.equal(1, #json.data)
          assert.equal("test-ws-example.com", json.data[1].host)
        end)
      end)

      describe('#Cache Invalidation:', function()
        local cache_key, cookie

        local function check_cache(expected_status, cache_key)
          local res = assert(client:send {
            method = "GET",
            path = "/cache/" .. cache_key,
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = super_admin.username,
            },
          })

          local json = assert.res_status(expected_status, res)

          return cjson.decode(json)
        end

        lazy_setup(function()
          cookie = get_admin_cookie_basic_auth(client, super_admin.username, 'hunter1')

          -- by default, rbac_user uses primary_key with no-workspace to generates cache_key.
          cache_key = db.rbac_users:cache_key(super_admin.rbac_user.id, '', '', '', '', true)
        end)

        it("updates rbac_users cache when admin updates rbac token", function()
          local cache_token, new_cache_token

          -- access "/" endpoint to trigger authentication process.
          -- rbac user should be cached.
          do
            local res = assert(client:send {
              method = "GET",
              path = "/",
              headers = {
                ["cookie"] = cookie,
                ["Kong-Admin-User"] = super_admin.username,
              },
            })

            assert.res_status(200, res)
            cache_token = check_cache(200, cache_key).user_token
          end

          -- updates rbac_user token via admin endpoint,
          -- expects difference of user_token in cookie,
          -- if cache has been invalidated.
          -- see 'rbac.get_user()' and
          -- 'cache invalidation' in 'runloop'.
          do
            local token = utils.uuid()

            local res = assert(client:send {
              method = "PATCH",
              path = "/admins/self/token",
              headers = {
                ["cookie"] = cookie,
                ["Kong-Admin-User"] = super_admin.username,
                ["Content-Type"] = "application/json"
              },
              body = {
                token = token
              }
            })

            assert.res_status(200, res)
            new_cache_token = check_cache(200, cache_key).user_token
            assert.not_equal(cache_token, new_cache_token)
          end
        end)
      end)
    end)

    pending("key-auth authentication", function()
      local super_admin, read_only_admin

      setup(function()
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
        helpers.stop_kong()
        if client then
          client:close()
        end
      end)

      describe("GET", function()
        it("returns 200 when authenticated with credentials", function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              apikey = "hunter1",
              ["Kong-Admin-User"] = super_admin.username,
            }
          })
          assert.res_status(200, res)

          local cookie_key_auth = res.headers["Set-Cookie"]

          res = assert(client:send {
            method = "GET",
            path = "/",
            headers = {
              cookie = cookie_key_auth,
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("Welcome to kong", json.tagline)
        end)

        it("returns 401 when authenticated with invalid password", function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              apikey = "my-key-is-wrong",
              ["Kong-Admin-User"] = super_admin.username,
            }
          })

          assert.res_status(401, res)
        end)

        it("returns 401 when authenticated with mismatched user/credentials",
          function()
          local res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              apikey = "hunter1",
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          })

          assert.res_status(401, res)
        end)
      end)
    end)

    describe("ldap-auth-advanced - authentication groups", function()
      local super_admin, read_only_admin, other_ws_admin

      lazy_setup(function()
        truncate_tables(db)

        assert(helpers.start_kong({
          plugins = "bundled, ldap-auth-advanced",
          database   = strategy,
          admin_gui_auth = "ldap-auth-advanced",
          enforce_rbac = "on",
          admin_gui_auth_conf = '{"attribute":"cn","base_dn":"cn=users,dc=ldap,dc=mashape,dc=com","bind_dn":"cn=ophelia,cn=users,dc=ldap,dc=mashape,dc=com","ldap_password":"passw2rd1111A$","cache_ttl":2,"header_type":"Basic","keepalive":60000,"ldap_host":"localhost","ldap_port":389,"start_tls":false,"timeout":10000,"verify_ldap_host":true}',
          rbac_auth_header = 'Kong-Admin-Token',
          smtp_mock = true,
        }))

        client = assert(helpers.admin_client())

        local ws = setup_ws_defaults(dao, db) -- default workspace

        super_admin = admin(db, ws, 'MacBeth')
        read_only_admin = admin(db, ws, 'Ophelia')

        local read_only_role = assert(db.rbac_roles:select_by_name('read-only'))
        local super_admin_role = assert(db.rbac_roles:select_by_name('super-admin'))
        local group1 = db.groups:insert({ name = 'test-group-1' })
        local group2 = db.groups:insert({ name = 'test-group-2' })
        local group3 = db.groups:insert({ name = 'test-group-3' })

        assert(db.group_rbac_roles:insert({
          group = group1,
          rbac_role = { id = super_admin_role.id },
          workspace = ws,
        }))
        assert(db.group_rbac_roles:insert({
          group = group2,
          rbac_role = { id = read_only_role.id },
          workspace = ws,
        }))

        -- give the super admin a non ldap-specified role
        local user_specified_role = db.rbac_roles:insert({ name = "no-read-service" })
        post(client, "/rbac/roles/no-read-service/endpoints", {
          workspace = "default",
          endpoint = "/services",
          actions = "read",
          negative = true,
        }, { ['Kong-Admin-Token'] = 'letmein-default' }, 201)
        assert(db.rbac_user_roles:insert({
          user = super_admin.rbac_user,
          role = user_specified_role,
        }))

        local another_ws = setup_ws_defaults(dao, db, 'another-one')
        other_ws_admin = admin(db, ws, 'Hamlet')
        local another_role = db.rbac_roles:insert({ name = "workspace-super-admin" })
        post(client, "/another-one/rbac/roles/workspace-super-admin/endpoints", {
          workspace = "another-one",
          endpoint = "*",
          actions = "create,read,update,delete",
          negative = false,
        }, { ['Kong-Admin-Token'] = 'letmein-default' }, 201)
        ngx.ctx.workspaces = {}
        assert(db.group_rbac_roles:insert({
          group = group3,
          rbac_role = { id = another_role.id },
          workspace = another_ws,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if client then
          client:close()
        end
      end)

      describe("groups - rbac roles mapped from ldap groups", function()
        it("read-only user - can login and only read resources", function()
          local cookie = get_admin_cookie_basic_auth(client, read_only_admin.username,
                                                     'passw2rd1111A$')
          local res = assert(client:send({
            method = "GET",
            path = "/userinfo",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = read_only_admin.username,
            }
          }))

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same({"test-group-2"}, json.groups)
          assert.same({ ["*"] = { ["*"] = { actions = { "read" },
                      negative = false } }}, json.permissions.endpoints)

          res = assert(client:send({
            method = "POST",
            path = "/consumers",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = read_only_admin.username,
              ["Content-Type"]     = "application/json",
            },
            body = {
              username = "somebody-that-i-used-to-know"
            }
          }))

          -- cannot create consumers
          assert.res_status(403, res)

          res = assert(client:send({
            method = "GET",
            path = "/consumers",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = read_only_admin.username,
            },
          }))

          -- but can read consumers
          assert.res_status(200, res)
        end)

        it("super-admin user - can login and read/create resources", function()
          local cookie = get_admin_cookie_basic_auth(client, super_admin.username,
                                                     'passw2rd1111A$')
          local res = client:send {
            method = "GET",
            path = "/userinfo",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = super_admin.username,
            }
          }

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same({"test-group-1", "test-group-3"}, json.groups)
          assert.same({ "delete", "create", "update", "read" },
                      json.permissions.endpoints["*"]["*"].actions)

          res = assert(client:send({
            method = "POST",
            path = "/consumers",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = super_admin.username,
              ["Content-Type"]     = "application/json",
            },
            body = {
              username = "somebody-that-i-used-to-know"
            }
          }))

          assert.res_status(201, res)
        end)

        it("super-admin user - user defined roles are applied", function()
          local cookie = get_admin_cookie_basic_auth(client, super_admin.username, 'passw2rd1111A$')
          local res = client:send {
            method = "GET",
            path = "/services",
            headers = {
              ["cookie"] = cookie,
              ["Kong-Admin-User"] = super_admin.username,
            }
          }

          assert.res_status(403, res)
        end)

        it("groups with roles in another workspace are applied", function()
          local cookie = get_admin_cookie_basic_auth(client, other_ws_admin.username,
                                                     'passw2rd1111A$')
          local req = function (path)
            return assert(client:send({
              method = "GET",
              path = path,
              headers = {
                ["cookie"] = cookie,
                ["Kong-Admin-User"] = other_ws_admin.username,
              }
            }))
          end

          local res = req("/userinfo")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({"test-group-3"}, json.groups)

          -- can only access entities in their workspace
          res = req("/services")
          assert.res_status(403, res)

          res = req("/another-one/services")
          assert.res_status(200, res)
        end)
      end)
    end)

    describe("login attempts", function()
      local request_invalid = function (username, times)
        local res
        for i=1, times or 1 do
          res = assert(client:send {
            method = "GET",
            path = "/auth",
            headers = {
              ["Authorization"] = "Basic "
                .. ngx.encode_base64(username .. ":this-password-is-bad" .. i),
              ["Kong-Admin-User"] = username,
            }
          })
          assert.res_status(401, res)
        end

        -- only returning the last response is required for now
        return res
      end

      describe("lockout", function()
        describe("default - unlimited attempts", function()
          local super_admin

          lazy_setup(function()
            truncate_tables(db)

            assert(helpers.start_kong({
              database   = strategy,
              admin_gui_auth = "basic-auth",
              enforce_rbac = "on",
              admin_gui_auth_config = "{ \"hide_credentials\": true }",
              rbac_auth_header = 'Kong-Admin-Token',
              -- admin_gui_auth_login_attempts = 0, DEFAULT VALUE
              smtp_mock = true
            }))

            client = assert(helpers.admin_client())

            local ws = setup_ws_defaults(dao, db, workspaces.DEFAULT_WORKSPACE)
            super_admin = admin(db, ws, 'mars', 'super-admin','test@konghq.com')

            assert(db.basicauth_credentials:insert {
              username    = super_admin.username,
              password    = "hunter1",
              consumer = {
                id = super_admin.consumer.id,
              },
            })
          end)

          lazy_teardown(function()
            helpers.stop_kong()
            if client then
              client:close()
            end
          end)

          it("GET - infinite attempts", function()
            request_invalid(super_admin.username, 10)
            assert.is_nil(db.login_attempts:select({consumer = super_admin.consumer}))
          end)
        end)

        describe("max attempts", function()
          local super_admin, read_only_admin1, read_only_admin2, read_only_admin3

          lazy_setup(function()
            truncate_tables(db)

            assert(helpers.start_kong({
              database   = strategy,
              admin_gui_auth = "basic-auth",
              enforce_rbac = "on",
              admin_gui_auth_config = "{ \"hide_credentials\": true }",
              rbac_auth_header = 'Kong-Admin-Token',
              smtp_mock = true,
              admin_gui_auth_login_attempts = 7,
            }))

            client = assert(helpers.admin_client())

            local ws = setup_ws_defaults(dao, db, workspaces.DEFAULT_WORKSPACE)
            super_admin = admin(db, ws, 'mars', 'super-admin','test@konghq.com')
            read_only_admin1 = admin(db, ws, 'gruce1', 'read-only', 'test1@konghq.com')
            read_only_admin2 = admin(db, ws, 'gruce2', 'read-only', 'test2@konghq.com')
            read_only_admin3 = admin(db, ws, 'gruce3', 'read-only', 'test3@konghq.com')

            assert(db.basicauth_credentials:insert {
              username    = super_admin.username,
              password    = "hunter1",
              consumer = {
                id = super_admin.consumer.id,
              },
            })

            assert(db.basicauth_credentials:insert {
              username    = read_only_admin1.username,
              password    = "hunter2",
              consumer = {
                id = read_only_admin1.consumer.id,
              },
            })

            assert(db.basicauth_credentials:insert {
              username    = read_only_admin2.username,
              password    = "hunter2",
              consumer = {
                id = read_only_admin2.consumer.id,
              },
            })

            assert(db.basicauth_credentials:insert {
              username    = read_only_admin3.username,
              password    = "hunter2",
              consumer = {
                id = read_only_admin3.consumer.id,
              },
            })
          end)

          lazy_teardown(function()
            helpers.stop_kong()
            if client then
              client:close()
            end
          end)

          describe("GET", function()
            it("user is allowed access", function ()
              local res = assert(client:send {
                method = "GET",
                path = "/auth",
                headers = {
                  ["Authorization"] = "Basic "
                    .. ngx.encode_base64(read_only_admin1.username .. ":hunter2"),
                  ["Kong-Admin-User"] = read_only_admin1.username,
                }
              })

              assert.res_status(200, res)
              assert.is_nil(db.login_attempts:select({consumer = super_admin.consumer}))
            end)

            it("user is denied access", function ()
              local res = request_invalid(super_admin.username)

              assert.res_status(401, res)
              assert.equals(1, db.login_attempts:select({consumer = super_admin.consumer}).attempts["127.0.0.1"])
            end)

            it("user is denied access - different consumer", function ()
              local res = request_invalid(read_only_admin1.username, 3)

              assert.res_status(401, res)
              assert.equals(3, db.login_attempts:select({consumer = read_only_admin1.consumer}).attempts["127.0.0.1"])
            end)

            it("user is locked out after max login attempts", function ()
              request_invalid(read_only_admin2.username, 7)
              assert.equals(7, db.login_attempts:select({consumer = read_only_admin2.consumer}).attempts["127.0.0.1"])

              -- Now that user is LOCKED_OUT, check to make sure that even a valid
              -- password will not work
              local res = assert(client:send {
                method = "GET",
                path = "/auth",
                headers = {
                  ["Authorization"] = "Basic "
                    .. ngx.encode_base64(read_only_admin2.username .. ":hunter2"),
                  ["Kong-Admin-User"] = read_only_admin2.username,
                }
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)
            end)

            it("attempts are reset after successful login", function ()
              request_invalid(read_only_admin3.username, 2)
              assert.equals(2, db.login_attempts:select({consumer = read_only_admin3.consumer}).attempts["127.0.0.1"])

              local res = assert(client:send {
                method = "GET",
                path = "/auth",
                headers = {
                  ["Authorization"] = "Basic "
                    .. ngx.encode_base64(read_only_admin3.username .. ":hunter2"),
                  ["Kong-Admin-User"] = read_only_admin3.username,
                }
              })

              assert.res_status(200, res)
              assert.is_nil(db.login_attempts:select({consumer = read_only_admin3.consumer}))
            end)

            it("attempts are reset after forgot password", function ()
              -- lock the admin out
              request_invalid(read_only_admin3.username, 7)
              assert.equals(7, db.login_attempts:select({consumer = read_only_admin3.consumer}).attempts["127.0.0.1"])

              -- create a token for updating password
              local jwt = secrets.create(read_only_admin3.consumer, "localhost",
                                         ngx.time() + 100000)

             -- update their password
              local res = assert(client:send {
                method = "PATCH",
                path  = "/admins/password_resets",
                headers = {
                  ["Content-Type"] = "application/json",
                },
                body  = {
                  email = read_only_admin3.email,
                  password = "my-new-password",
                  token = jwt,
                }
              })
              assert.res_status(200, res)

              -- use their new password
              res = assert(client:send {
                method = "GET",
                path = "/auth",
                headers = {
                  ["Authorization"] = "Basic " ..
                    ngx.encode_base64(read_only_admin3.username .. ":my-new-password"),
                  ["Kong-Admin-User"] = read_only_admin3.username,
                }
              })
              assert.res_status(200, res)

              -- check that login attempts are reset
              assert.is_nil(db.login_attempts:select({consumer = read_only_admin3.consumer}))
            end)
          end)
        end)
      end)
    end)
  end)
end
