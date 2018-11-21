local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"
local workspaces = require "kong.workspaces"

for _, strategy in helpers.each_strategy() do

  describe("admin_helpers with #" .. strategy, function()
    local dao
    local default_ws, another_ws
    local admins = {}

    setup(function()
      _, _, dao = helpers.get_db_utils(strategy)

      default_ws = assert(dao.workspaces:find_all({ name = "default" })[1])

      another_ws = assert(dao.workspaces:insert({ name = "ws1" }))

      for i = 1, 4 do
        -- half the admins are in each workspace,
        -- and half have a null custom_id
        local ws_to_use = i % 2 == 0 and another_ws or default_ws
        local custom_id = i % 2 == 0 and ("admin-" .. i) or ngx.null

        local cons = assert(dao.consumers:run_with_ws_scope (
          { ws_to_use },
          dao.consumers.insert,
          {
            username = "admin-" .. i,
            custom_id = custom_id,
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

        cons.rbac_user = user
        admins[i] = cons
      end
    end)

    describe("validate admins", function()
      it("requires unique consumer.username", function()
        local params = {
          username = "admin-1",
          email = "unique@test.com",
        }

        local res, match, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.not_nil(match.rbac_user)
        assert.is_false(res)
      end)

      it("requires unique consumer.custom_id", function()
        local params = {
          username = "i-am-unique",
          custom_id = "admin-1",
          email = "unique@test.com",
        }

        local res, match, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.not_nil(match.rbac_user)
        assert.is_false(res)
      end)

      it ("doesn't consider null consumer.custom_ids to match", function()
        -- admins 1 and 3 have null custom_id. Is admin-99 considered valid?
        local params = {
          username = "admin-99",
          custom_id = ngx.null,
          email = "admin-99@test.com",
        }

        local res, match, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.is_nil(match)
        assert.is_true(res)
      end)

      it("requires unique consumer.email", function()
        local params = {
          username = "i-am-unique",
          custom_id = "i-am-unique",
          email = "admin-2@test.com",
        }

        local res, match, err = admins_helpers.validate(params, dao, "POST")

        assert.is_nil(err)
        assert.not_nil(match.consumer)
        assert.is_false(res)
      end)

      it("works on update as well as create", function()
        local params = {
          username = "admin-1",
          custom_id = "admin-1",
          email = "admin-2@test.com",
        }

        local res, match, err = admins_helpers.validate(params, dao, "PATCH")

        assert.is_nil(err)
        assert.not_nil(match.consumer)
        assert.is_false(res)
      end)
    end)

    describe("update", function()
      local admin

      setup(function()
        admin = assert(dao.consumers:run_with_ws_scope (
          { default_ws },
          dao.consumers.insert,
          {
            username = "admin",
            custom_id = ngx.null,
            email = "admin@test.com",
            type = enums.CONSUMERS.TYPE.ADMIN,
          })
        )

        local user = assert(dao.rbac_users:insert {
          name = admin.username,
          user_token = utils.uuid(),
          enabled = true,
        })

        dao.consumers_rbac_users_map:insert {
          consumer_id = admin.id,
          user_id = user.id,
        }

        admin.rbac_user = user
      end)

      it("doesn't fail when admin doesn't have a credential", function()
        local res = admins_helpers.update({ custom_id = "foo" }, admins[3], admins[3].rbac_user)

        -- should look just like what we passed in, but with a custom_id
        local expected = utils.deep_copy(admins[3])
        expected.custom_id = "foo"

        assert.same({ code = 200, body = expected }, res)
      end)

      it("updates a null field to a non-null one", function()
        local new_custom_id = "admin-custom-id"
        local params = {
          username = admin.username,
          custom_id = new_custom_id,
          email = admin.email,
        }

        local res = admins_helpers.update(params, admin, admin.rbac_user)
        assert.same(new_custom_id, res.body.custom_id)
      end)

      it("updates a non-null field to null", function()
        local params = {
          username = admin.username,
          custom_id = ngx.null,
          email = admin.email,
        }

        local res = admins_helpers.update(params, admin, admin.rbac_user)
        assert.same(nil, res.body.custom_id)
      end)
    end)

    describe("link_to_workspace", function()
      it("links an admin to another workspace", function()
        -- odd-numbered admins are in default_ws
        local admin, err = admins_helpers.link_to_workspace(admins[1], dao, another_ws)

        assert.is_nil(err)

        -- only returning the consumer, not the rbac user
        local expected = utils.shallow_copy(admins[1])
        assert.same(admin, expected)

        local ws_list, err = workspaces.find_workspaces_by_entity({
          workspace_id = another_ws.id,
          entity_type = "consumers",
          entity_id = admins[1].id,
        })

        assert.is_nil(err)
        assert.not_nil(ws_list)
        assert.same(ws_list[1].workspace_id, another_ws.id)

        ws_list, err = workspaces.find_workspaces_by_entity({
          workspace_id = another_ws.id,
          entity_type = "rbac_users",
          entity_id = admins[1].rbac_user.id,
        })

        assert.is_nil(err)
        assert.not_nil(ws_list)
        assert.same(ws_list[1].workspace_id, another_ws.id)
      end)

      it("returns nil when the object to link is not a valid admin", function()
        -- this happens when the consumer or the rbac user that is passed in
        -- is not part of an admin object; e.g., a stand-alone rbac user
        local user = assert(dao.rbac_users:insert {
          name = "vanilla-rbac-user",
          user_token = utils.uuid(),
          enabled = true,
        })

        local admin, err = admins_helpers.link_to_workspace(
                           { rbac_user = user }, dao, another_ws)

        assert.is_nil(err)
        assert.is_nil(admin)
      end)
    end)
  end)
end
