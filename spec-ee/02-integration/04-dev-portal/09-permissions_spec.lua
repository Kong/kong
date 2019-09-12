local helpers      = require "spec.helpers"
local permissions = require "kong.portal.permissions"
local constants   = require "kong.constants"
local workspaces  = require "kong.workspaces"
local ee_helpers = require "spec-ee.helpers"
local cjson = require "cjson"


local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"


local function close_clients(clients)
  for idx, client in ipairs(clients) do
    client:close()
  end
end


local function client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res.body_reader()

  close_clients({ client })
  return res
end


local function api_client_request(params)
  local portal_api_client = assert(ee_helpers.portal_api_client())
  local res = assert(portal_api_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_api_client })
  return res
end


local function gui_client_request(params)
  local portal_gui_client = assert(ee_helpers.portal_gui_client())
  local res = assert(portal_gui_client:send(params))
  res.body = res.body_reader()

  close_clients({ portal_gui_client })
  return res
end


local function register_developer(params, workspace)
  workspace = workspace or "default"
  return api_client_request({
    method = "POST",
    path = "/" .. workspace .. "/register",
    body = params,
    headers = {["Content-Type"] = "application/json"},
  })
end


local function configure_portal(db)
  return db.workspaces:upsert_by_name("default", {
    name = "default",
    config = {
      portal = true,
    },
  })
end


for _, strategy in helpers.each_strategy() do
  describe("Portal Permissions[" .. strategy .. "]", function()
    describe("can_read", function()
      local bp, db
      setup(function()
        bp, db = helpers.get_db_utils(strategy)
        local s = require "kong.singletons"
        s.configuration = { portal_auth = "basic-auth" }
        local store = {}
        kong.cache = {
          get = function(_, key, _, f, ...)
            store[key] = store[key] or f(...)
            return store[key]
          end,
          invalidate = function(_, key)
            store[key] = nil
            return true
          end,
        }
      end)

      before_each(function()
        assert(db:truncate("rbac_role_endpoints"))
        assert(db:truncate("rbac_roles"))
        assert(db:truncate("developers"))
        assert(db:truncate("consumers"))
        assert(db:truncate("files"))
        assert(db:truncate("workspaces"))
        assert(db:truncate("basicauth_credentials"))
      end)

      it("returns false if the developer has no roles", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        local dev = bp.developers:insert({
          email = "a@a.co" ,
          meta = '{"full_name":"x"}',
          password = "test",
        })
        local file = assert(db.files:insert({
          path = "content/foo.txt",
          contents = [[
            ---
            stuff: things
            ---
          ]]
        }))
        assert.is_falsy(permissions.can_read(dev, ws, file.path))
      end)

      it("returns false if the developer does not have the needed roles", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "blue" })

        local dev = bp.developers:insert({
          email = "a@a.co" ,
          meta = '{"full_name":"x"}',
          password = "test",
          roles = { "blue" },
        })
        local file = assert(db.files:insert({
          path = "content/foo.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }))
        assert.is_falsy(permissions.can_read(dev, ws, file.path))
      end)

      it("returns true if the developer has permissions to access the given file", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "blue" })

        local dev = bp.developers:insert({
          email = "a@a.co" ,
          meta = '{"full_name":"x"}',
          password = "test",
          roles = { "red" },
        })
        local file = assert(db.files:insert({
          path = "content/foo.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }))

        assert.is_truthy(permissions.can_read(dev, ws, file.path))
      end)

      it("returns true if developer.skip_portal_rbac (portal auth disabled)", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "blue" })

        local dev = { skip_portal_rbac = true }

        local file = assert(db.files:insert({
          path = "content/foo.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }))

        assert.is_truthy(permissions.can_read(dev, ws, file.path))
      end)
    end)

    describe("set_file_permissions", function()
      local bp, db
      setup(function()
        bp, db = helpers.get_db_utils(strategy)
        local s = require "kong.singletons"
        s.configuration = { portal_auth = "basic-auth" }
        local store = {}
        kong.cache = {
          get = function(_, key, _, f, ...)
            store[key] = store[key] or f(...)
            return store[key]
          end,
          invalidate = function(_, key)
            store[key] = nil
            return true
          end,
        }
      end)

      before_each(function()
        assert(db:truncate("rbac_role_endpoints"))
        assert(db:truncate("rbac_roles"))
        assert(db:truncate("developers"))
        assert(db:truncate("consumers"))
        assert(db:truncate("files"))
        assert(db:truncate("workspaces"))
        assert(db:truncate("basicauth_credentials"))
      end)

      it("returns nil, error if contents is not valid stringified yaml", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = "---..,msdfak",
        }

        local ok, err = permissions.set_file_permissions(file, ws)
        assert.is_nil(ok)
        assert.equals("contents: cannot parse, files with 'content/' prefix must have valid headmatter/body syntax", err)

        local rows = db.rbac_role_endpoints:select_all()
        assert.same({}, rows)
      end)

      it("returns nil, error if contents is empty", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = nil,
        }

        local ok, err = permissions.set_file_permissions(file, ws)
        assert.is_nil(ok)
        assert.equals("contents: missing required field", err)

        local rows = db.rbac_role_endpoints:select_all()
        assert.same({}, rows)
      end)

      it("returns nil, error if attempting to set permissions for a role that does not exist", function()
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }

        local ok, err = permissions.set_file_permissions(file, ws)
        assert.is_nil(ok)
        assert.equals("could not find role: red", err)

        local rows = db.rbac_role_endpoints:select_all()
        assert.same({}, rows)
      end)

      it("returns true but does not set any permissions if prefix is not 'content/'", function()
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "something/else.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()
        assert.same({}, rows)
      end)

      it("returns true and sets permissions if prefix is 'content'", function()
        local role = bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()
        assert.equals(1, #rows)
        assert.equals("/" .. file.path, rows[1].endpoint)
        assert.equals(role.id, rows[1].role.id)
      end)

      it("handles multple roles", function()
        local red_role = bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        local blue_role = bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "blue" })

        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["red", "blue"]
            ---
          ]],
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()

        assert.equals(2, #rows)

        local roles_matched = {}

        for i, row in ipairs(rows) do
          assert.equals("/" .. file.path, rows[i].endpoint)

          if rows[i].role.id == red_role.id then
            roles_matched.red = true
          elseif rows[i].role.id == blue_role.id then
            roles_matched.blue = true
          end
        end

        assert.is_truthy(roles_matched.red)
        assert.is_truthy(roles_matched.blue)
      end)

      it("returns true and updates permissions if they exist", function()
        local red_role = bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        local blue_role = bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "blue" })
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]],
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()
        assert.equals(1, #rows)
        assert.equals("/" .. file.path, rows[1].endpoint)
        assert.equals(red_role.id, rows[1].role.id)

        file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["blue"]
            ---
          ]],
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()
        assert.equals(1, #rows)
        assert.equals("/" .. file.path, rows[1].endpoint)
        assert.equals(blue_role.id, rows[1].role.id)
      end)
    end)

    describe("delete_file_permissions", function()
      local bp, db
      setup(function()
        bp, db = helpers.get_db_utils(strategy)
        local s = require "kong.singletons"
        s.configuration = { portal_auth = "basic-auth" }
        local store = {}
        kong.cache = {
          get = function(_, key, _, f, ...)
            store[key] = store[key] or f(...)
            return store[key]
          end,
          invalidate = function(_, key)
            store[key] = nil
            return true
          end,
        }
      end)

      before_each(function()
        assert(db:truncate("rbac_role_endpoints"))
        assert(db:truncate("rbac_roles"))
        assert(db:truncate("developers"))
        assert(db:truncate("consumers"))
        assert(db:truncate("files"))
        assert(db:truncate("workspaces"))
        assert(db:truncate("basicauth_credentials"))
      end)

      it("returns nil, error if contents is not valid stringified yaml", function()
        -- add new permissions to a file
        bp.rbac_roles:insert({ name = constants.PORTAL_PREFIX .. "red" })
        local ws = workspaces.DEFAULT_WORKSPACE
        local file = {
          path = "content/file.txt",
          contents = [[
            ---
            readable_by: ["red"]
            ---
          ]]
        }

        assert.is_truthy(permissions.set_file_permissions(file, ws))

        local rows = db.rbac_role_endpoints:select_all()
        assert.equals("/" .. file.path, rows[1].endpoint)

        -- delete permissions
        assert.is_truthy(permissions.delete_file_permissions(file, ws))
        local rows = db.rbac_role_endpoints:select_all()
        assert.same({}, rows)
      end)
    end)

    describe("Fetching pages", function()
      local roles = {"red", "blue"}

      local content_files = {
        red = {
          path = "content/red.txt",
          contents = [[
            ---
            readable_by: ["red"]
            layout: red.html
            ---
          ]]
        },
        blue = {
          path = "content/blue.txt",
          contents = [[
            ---
            readable_by: ["blue"]
            layout: blue.html
            ---
          ]],

        },
        red_blue = {
          path = "content/red_blue.txt",
          contents = [[
            ---
            readable_by: ["red", "blue"]
            layout: red_blue.html
            ---
          ]]
        },
        star = {
          path = "content/star.txt",
          contents = [[
            ---
            readable_by: "*"
            layout: star.html
            ---
          ]]
        },
        login = {
          path = "content/login.txt",
          contents = [[
            ---
            layout: login.html
            ---
          ]],
        },
        unauthorized = {
          path = "content/unauthorized.txt",
          contents = [[
            ---
            layout: unauthorized.html
            ---
          ]],
        },
        ["404"] = {
          path = "content/404.txt",
          contents = [[
            ---
            layout: 404.html
            ---
          ]],
        }
      }

      describe("Unauthenticated User", function()
        local db

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong()
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end
        end)

        it("redirects to login when requesting red page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("redirects to login when requesting blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("redirects to login when requesting red_blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red_blue",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("redirects to login when requesting star page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the login page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/login",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the 404 page when requesting a non existent page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/nope",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("404", body)
        end)
      end)

      describe("Developer with red role", function()
        local db

        local developer = {
          name = "red",
          roles = { "red" },
        }

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong(nil, true)
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Conf file
          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "portal.conf.yaml",
              contents = [[
                name: Test Portal
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Developer
          local res = register_developer({
            email = developer.name .."@konghq.com",
            key = developer.name,
            meta = '{"full_name":"' .. developer.name .. '"}',
            roles = developer.roles,
          })

          local json = cjson.decode(res.body)
          developer.id = json.developer.id

          -- Login
          local res = api_client_request({method = "GET",
            path = "/auth",
            headers = {
              ['apikey'] = developer.name
            }
          })

          developer.cookie = assert.response(res).has.header("Set-Cookie")
        end)

        it("serves the red page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red", body)
        end)

        it("redirects to unauthorized when requesting blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("serves the red_blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red_blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red_blue", body)
        end)

        it("serves the star page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("star", body)
        end)

        it("serves the login page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/login",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the 404 page when requesting a non existent page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/nope",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("404", body)
        end)

        it("serves the blue page when blue role is added", function()
          client_request({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              roles = {"red", "blue"}
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("blue", body)
        end)


        it("redirects to unauthorized when requesting red page (role removed)", function()
          client_request({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              roles = {}
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "PATCH",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("redirects to unauthorized when requesting red page (file permissions changed)", function()
          client_request({
            method = "PATCH",
            path = "/files/content/red.txt",
            body = {
              contents = [[
                ---
                readable_by: ["blue"]
                layout: red.html
                ---
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "PATCH",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)
      end)

      describe("Developer with blue role", function()
        local db

        local developer = {
          name = "blue",
          roles = { "blue" },
        }

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong()
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Conf file
          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "portal.conf.yaml",
              contents = [[
                name: Test Portal
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Developer
          local res = register_developer({
            email = developer.name .."@konghq.com",
            key = developer.name,
            meta = '{"full_name":"' .. developer.name .. '"}',
            roles = developer.roles,
          })

          local json = cjson.decode(res.body)
          developer.id = json.developer.id

          -- Login
          local res = api_client_request({method = "GET",
            path = "/auth",
            headers = {
              ['apikey'] = developer.name
            }
          })

          developer.cookie = assert.response(res).has.header("Set-Cookie")
        end)

        it("redirects to unauthorized when requesting red page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("serves the blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("blue", body)
        end)

        it("serves the red_blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red_blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red_blue", body)
        end)

        it("serves the star page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("star", body)
        end)

        it("serves the login page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/login",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the 404 page when requesting a non existent page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/nope",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("404", body)
        end)

        it("serves the red page when red role is added", function()
          client_request({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              roles = {"red", "blue"}
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red", body)
        end)

        it("redirects to unauthorized when requesting blue page (role removed)", function()
          client_request({
            method = "PATCH",
            path = "/developers/" .. developer.id,
            body = {
              roles = {}
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "PATCH",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("redirects to unauthorized when requesting blue page (file permissions changed)", function()
          client_request({
            method = "PATCH",
            path = "/files/content/blue.txt",
            body = {
              contents = [[
                ---
                readable_by: ["red"]
                layoute: blue.html
                ---
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local res = gui_client_request({
            method = "PATCH",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)
      end)

      describe("Developer with red and blue roles", function()
        local db

        local developer = {
          name = "red_blue",
          roles = { "red", "blue" },
        }

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong()
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Conf file
          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "portal.conf.yaml",
              contents = [[
                name: Test Portal
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Developer
          local res = register_developer({
            email = developer.name .."@konghq.com",
            key = developer.name,
            meta = '{"full_name":"' .. developer.name .. '"}',
            roles = developer.roles,
          })

          local json = cjson.decode(res.body)
          developer.id = json.developer.id

          -- Login
          local res = api_client_request({method = "GET",
            path = "/auth",
            headers = {
              ['apikey'] = developer.name
            }
          })

          developer.cookie = assert.response(res).has.header("Set-Cookie")
        end)

        it("serves the red page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red", body)
        end)

        it("serves the blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("blue", body)
        end)

        it("serves the red_blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red_blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("red_blue", body)
        end)

        it("serves the star page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("star", body)
        end)

        it("serves the login page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/login",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the 404 page when requesting a non existent page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/nope",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("404", body)
        end)
      end)

      describe("Developer with no roles", function()
        local db

        local developer = {
          name = "no_roles",
          roles = {},
        }

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong()
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Conf file
          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "portal.conf.yaml",
              contents = [[
                name: Test Portal
              ]],
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Developer
          local res = register_developer({
            email = developer.name .."@konghq.com",
            key = developer.name,
            meta = '{"full_name":"' .. developer.name .. '"}',
            roles = developer.roles,
          })

          local json = cjson.decode(res.body)
          developer.id = json.developer.id

          -- Login
          local res = api_client_request({method = "GET",
            path = "/auth",
            headers = {
              ['apikey'] = developer.name
            }
          })

          developer.cookie = assert.response(res).has.header("Set-Cookie")
        end)

        it("redirects to unauthorized when requesting red page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("redirects to unauthorized when requesting blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("redirects to unauthorized when requesting red_blue page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/red_blue",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)

        it("serves the star page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("star", body)
        end)

        it("serves the login page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/login",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("serves the 404 page when requesting a non existent page", function()
          local res = gui_client_request({
            method = "GET",
            path = "/default/nope",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("404", body)
        end)
      end)

      describe("portal.conf.yaml auth", function()
        local db

        local developer = {
          name = "no_roles",
          roles = {},
        }

        lazy_setup(function()
          _, db, _ = helpers.get_db_utils(strategy)

          assert(helpers.start_kong({
            database    = strategy,
            portal      = true,
            portal_is_legacy = false,
            portal_auth = "key-auth",
            portal_auto_approve = true,
            portal_session_conf = PORTAL_SESSION_CONF,
          }))
        end)

        lazy_teardown(function()
          assert(db:truncate())
          helpers.stop_kong()
        end)

        before_each(function()
          assert(db:truncate("rbac_role_endpoints"))
          assert(db:truncate("rbac_roles"))
          assert(db:truncate("developers"))
          assert(db:truncate("consumers"))
          assert(db:truncate("files"))
          assert(db:truncate("workspaces"))
          assert(db:truncate("keyauth_credentials"))

          assert(configure_portal(db))

          -- Conf file
          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "portal.conf.yaml",
              contents = '{"name": "Test Portal"}',
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          -- Roles
          for _, role in ipairs(roles) do
            assert(client_request({
              method = "POST",
              path = "/developers/roles",
              body = {
                name = role
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Content/Layout
          for name, body in pairs(content_files) do
            assert(client_request({
              method = "POST",
              path = "/files",
              body = body,
              headers = {["Content-Type"] = "application/json"},
            }))

            assert(client_request({
              method = "POST",
              path = "/files",
              body = {
                path = "themes/default/layouts/" .. name .. ".html",
                contents = name,
              },
              headers = {["Content-Type"] = "application/json"},
            }))
          end

          -- Developer
          local res = register_developer({
            email = developer.name .."@konghq.com",
            key = developer.name,
            meta = '{"full_name":"' .. developer.name .. '"}',
            roles = developer.roles,
          })

          local json = cjson.decode(res.body)
          developer.id = json.developer.id

          -- Login
          local res = api_client_request({method = "GET",
            path = "/auth",
            headers = {
              ['apikey'] = developer.name
            }
          })

          developer.cookie = assert.response(res).has.header("Set-Cookie")
        end)

        it("redirects to redirect.login if set in conf", function()
          assert(client_request({
            method = "PATCH",
            path = "/files/portal.conf.yaml",
            body = {
              contents = cjson.encode({
                redirect = {
                  unauthenticated = "custom_login"
                }
              }),
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "content/custom_login.txt",
              contents = [[
                ---
                layout: custom_login.html
                ---
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "themes/default/layouts/custom_login.html",
              contents = "custom_login",
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("custom_login", body)
        end)

        it("redirects to login if redirect.login is not found", function()
          assert(client_request({
            method = "PATCH",
            path = "/files/portal.conf.yaml",
            body = {
              contents = cjson.encode({
                redirect = {
                  unauthenticated = "doesnt_exist"
                }
              }),
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local res = gui_client_request({
            method = "GET",
            path = "/default/star",
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("login", body)
        end)

        it("redirects to redirect.unauthorized if set in conf", function()
          assert(client_request({
            method = "PATCH",
            path = "/files/portal.conf.yaml",
            body = {
              contents = cjson.encode({
                redirect = {
                  unauthorized = "custom_unauthed"
                }
              }),
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "content/custom_unauthed.txt",
              contents = [[
                ---
                layout: custom_unauthed.html
                ---
              ]]
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          assert(client_request({
            method = "POST",
            path = "/files",
            body = {
              path = "themes/default/layouts/custom_unauthed.html",
              contents = "custom_unauthed",
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("custom_unauthed", body)
        end)

        it("redirects to unauthorized if redirect.unauthorized is not found", function()
          assert(client_request({
            method = "PATCH",
            path = "/files/portal.conf.yaml",
            body = {
              contents = cjson.encode({
                redirect = {
                  unauthorized = "doesnt_exist"
                }
              }),
            },
            headers = {["Content-Type"] = "application/json"},
          }))

          local res = gui_client_request({
            method = "GET",
            path = "/default/red",
            headers = {
              ["Cookie"] = developer.cookie,
            }
          })

          local status = res.status
          local body = res.body

          assert.equals(200, status)
          assert.equals("unauthorized", body)
        end)
      end)
    end)
  end)
end
