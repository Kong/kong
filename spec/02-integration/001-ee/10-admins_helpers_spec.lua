local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"

for _, strategy in helpers.each_strategy() do

  describe("admin_helpers", function()
    local dao
    local default_ws, another_ws

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)

      default_ws = assert(dao.workspaces:find_all({ name = "default" })[1])

      another_ws = assert(dao.workspaces:insert({ name = "ws1" }))

      local cons
      for i = 1, 4 do
        local ws_to_use = i % 2 == 0 and another_ws or default_ws

        cons = assert(dao.consumers:run_with_ws_scope (
          { ws_to_use },
          dao.consumers.insert,
          {
            username = "admin-" .. i,
            custom_id = "admin-" .. i,
            email = "admin-" .. i .. "@test.com",
            type = enums.CONSUMERS.TYPE.ADMIN,
          })
        )

        local user = assert(dao.rbac_users:insert {
          name = "admin-" .. i,
          user_token = utils.uuid(),
          enabled = true,
        })

        dao.consumers_rbac_users_map:insert {
          consumer_id = cons.id,
          user_id = user.id,
        }
      end
    end)

    describe("validate admins", function()
      it("requires unique consumer.username", function()
        local params = {
          username = "admin-1",
          email = "unique@test.com",
        }

        local res, msg, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.same("rbac_user already exists", msg)
        assert.is_false(res)
      end)

      it("requires unique consumer.custom_id", function()
        local params = {
          username = "i-am-unique",
          custom_id = "admin-1",
          email = "unique@test.com",
        }

        local res, msg, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.same("rbac_user already exists", msg)
        assert.is_false(res)
      end)

      it("requires unique consumer.email", function()
        local params = {
          username = "i-am-unique",
          custom_id = "i-am-unique",
          email = "admin-2@test.com",
        }

        local res, msg, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.same("consumer already exists", msg)
        assert.is_false(res)
      end)

      it("works on update as well as create", function()
        local params = {
          username = "admin-1",
          custom_id = "admin-1",
          email = "admin-2@test.com",
        }

        local res, msg, err = admins_helpers.validate(params, dao, "PATCH")

        assert.is_nil(err)
        assert.same("consumer already exists", msg)
        assert.is_false(res)
      end)
    end)
  end)
end
