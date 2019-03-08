local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local ee_helpers = require "spec-ee.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local rbac = require "kong.rbac"


for _, strategy in helpers.each_strategy() do
  describe("#flaky db #".. strategy .. " RBAC on admin route", function()
    local client
    local bp, db, dao
    local default_role_one, default_role_two, test_role

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
      ee_helpers.register_rbac_resources(db)

      assert(helpers.start_kong({
        enforce_rbac = "off",
        database = strategy,
      }))
      client = assert(helpers.admin_client())

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/users",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          name = "bob",
          user_token= "1234"
        },
      })

      local body = assert.res_status(201, res)
      local rbac_user = cjson.decode(body)

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/users/" .. rbac_user.name .. "/roles",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          roles = "super-admin",
        },
      })
      assert.res_status(201, res)


      default_role_one = assert(db.rbac_roles:select_by_name(rbac_user.name))

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/users",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          name = "foo",
          user_token= "12345"
        },
      })

      local body = assert.res_status(201, res)
      local rbac_user = cjson.decode(body)

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/users/" .. rbac_user.name .. "/roles",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          roles = "super-admin",
        },
      })
      assert.res_status(201, res)

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/roles",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          name = "test_role",
        },
      })

      local body = assert.res_status(201, res)
      test_role = cjson.decode(body)

      local res = assert(client:send {
        method = "POST",
        path  = "/rbac/roles/" .. test_role.name .. "/endpoints",
        headers = {
          ["Content-Type"]     = "application/json",
        },
        body  = {
          workspace = "*",
          endpoint  = "/some/path"
        },
      })

      assert.res_status(201, res)


      local rbac_default_roles = assert(dao.rbac_roles:find_all {
        name = rbac_user.name,
      })
      default_role_two = rbac_default_roles[1]

      if client then client:close() end
      helpers.stop_kong(nil, nil, true)
      assert(helpers.start_kong({
        enforce_rbac = "both",
        database = strategy,
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("default role", function()
      describe("POST", function ()
        it("should add entity when primary key is uuid", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/certificates",
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              cert=ssl_fixtures.cert,
              key=ssl_fixtures.key,
            },
          })

          local body = assert.res_status(201, res)
          local cert = cjson.decode(body)

          local in_db = assert(db.rbac_role_entities:select({ role_id = default_role_one.id, entity_id = cert.id}))
          assert.equal(cert.id, in_db.entity_id)
        end)
        it("should add entity when primary key is string", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/certificates",
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              cert=ssl_fixtures.cert,
              key=ssl_fixtures.key,
            },
          })

          local body = assert.res_status(201, res)
          local cert = cjson.decode(body)

          local res = assert(client:send {
            method = "POST",
            path  = "/snis",
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              name = "foo.com",
              ssl_certificate_id = cert.id
            },
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          local in_db = assert(db.rbac_role_entities:select({ role_id = default_role_one.id, entity_id = json.name}))
          assert.equal(json.name, in_db[1].entity_id)
        end)
        it("should remove role, entity relation when entity is deleted", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/certificates",
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              cert=ssl_fixtures.cert,
              key=ssl_fixtures.key,
              snis="bar.com"
            },
          })

          local body = assert.res_status(201, res)
          local cert = cjson.decode(body)

          local res = assert(client:send {
            method = "DELETE",
            path  = "/certificates/" .. cert.id,
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            }
          })
          assert.res_status(204, res)
          local in_db = assert(dao.rbac_role_entities:find_all {entity_id = cert.id})
          assert.equal(0, #in_db)
        end)
        it("should remove default role, entity relation when user is deleted", function()
          local res = assert(client:send {
            method = "POST",
            path  = "/certificates",
            headers = {
              ["Kong-Admin-Token"] = "12345",
              ["Content-Type"]     = "application/json",
            },
            body  = {
              cert=ssl_fixtures.cert,
              key=ssl_fixtures.key,
              snis="foobar.com"
            },
          })

          local body = assert.res_status(201, res)
          local cert = cjson.decode(body)
          local res = assert(client:send {
            method = "DELETE",
            path  = "/rbac/users/" .. default_role_two.name,
            headers = {
              ["Kong-Admin-Token"] = "12345",
              ["Content-Type"]     = "application/json",
            }
          })
          assert.res_status(204, res)
          -- XXX EE uncomment when find_all supports this
          -- local in_db = assert(dao.rbac_role_entities:find_all {entity_id = cert.id})
          -- assert.equal(0, #in_db)
          local in_db = assert(rbac.get_role_endpoints({id = default_role_two.id}))
          assert.equal(0, #in_db)
        end)
        it("should remove role, endpoint relation when role is deleted", function()
          -- local in_db = assert(db.rbac_role_endpoints:find_all({role_id = test_role.id}))
          local in_db = assert(rbac.get_role_endpoints(db, test_role))
          assert.equal(1, #in_db)
          local res = assert(client:send {
            method = "DELETE",
            path  = "/rbac/roles/" .. test_role.name,
            headers = {
              ["Kong-Admin-Token"] = "1234",
              ["Content-Type"]     = "application/json",
            }
          })
          assert.res_status(204, res)
          local in_db = assert(rbac.get_role_endpoints(db, test_role))
          assert.equal(0, #in_db)
        end)
      end)
    end)
  end)
end
