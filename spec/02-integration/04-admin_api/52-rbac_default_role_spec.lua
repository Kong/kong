local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local ee_helpers = require "spec.ee_helpers"


for _, strategy in helpers.each_strategy() do
  describe("RBAC on admin route", function()
    local client
    local dao
    local rbac_role, default_role

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      ee_helpers.register_rbac_resources(dao)

      local rbac_user = assert(dao.rbac_users:insert {
        name = "bob",
        user_token= "1234"
      })

      local rbac_roles = assert(dao.rbac_roles:find_all {
        name = "super-admin",
      })
      rbac_role = rbac_roles[1]

      assert(dao.rbac_user_roles:insert {
        role_id  = rbac_role.id,
        user_id  = rbac_user.id,
      })

      local rbac_default_roles = assert(dao.rbac_roles:find_all {
        name = rbac_user.name,
      })
      default_role = rbac_default_roles[1]

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
              cert="-----CERTIFICATE-----",
              key="-----CERTIFICATE-----",
            },
          })

          local body = assert.res_status(201, res)
          local cert = cjson.decode(body)

          local in_db = assert(dao.rbac_role_entities:find_all {role_id = default_role.id, entity_id = cert.id})
          assert.equal(cert.id, in_db[1].entity_id)
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
              cert="-----CERTIFICATE-----",
              key="-----CERTIFICATE-----",
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
          local in_db = assert(dao.rbac_role_entities:find_all {role_id = default_role.id, entity_id = json.name})
          assert.equal(json.name, in_db[1].entity_id)
        end)
      end)
    end)
  end)
end
