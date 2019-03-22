local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"

for _, strategy in helpers.each_strategy() do

  describe("admin_helpers with #" .. strategy, function()
    local db, factory
    local default_ws, another_ws
    local admins = {}

    lazy_setup(function()
      _, db, factory = helpers.get_db_utils(strategy)

      helpers.bootstrap_database(db)

      admins = db.admins

      singletons.db = db
      singletons.dao = factory

      default_ws = assert(workspaces.fetch_workspace("default"))
      another_ws = assert(db.workspaces:insert({ name = "ws1" }))

      for i = 1, 4 do
        -- half the admins are in each workspace,
        -- and half have a null custom_id
        local ws_to_use = i % 2 == 0 and another_ws or default_ws
        local custom_id = i % 2 == 0 and ("admin-" .. i) or ngx.null

        -- consumers are workspaceable, so need to have a ws in context
        ngx.ctx.workspaces = { ws_to_use }

        local admin = assert(db.admins:insert {
          email = "admin-" .. i .. "@test.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
          username = "admin-" .. i,
          custom_id = custom_id,
        })

        admins[i] = admin
      end
    end)

    lazy_teardown(function()
      db:truncate("basicauth_credentials")
      db:truncate("workspace_entities")
      db:truncate("workspaces")
      db:truncate("consumers")
      db:truncate("rbac_user_roles")
      db:truncate("rbac_roles")
      db:truncate("rbac_users")
      db:truncate("admins")

      ngx.shared.kong_cassandra:flush_expired()
    end)

    describe("find all admins", function()
      it("returns the right data structure", function()
        local res, err = admins_helpers.find_all()
        assert.is_nil(err)
        assert.same(4, #res.body['data'])
        assert.same(200, res.code)

        assert.not_nil(res.body['data'][1].created_at)
        assert.not_nil(res.body['data'][1].email)
        assert.not_nil(res.body['data'][1].id)
        assert.not_nil(res.body['data'][1].status)
        assert.not_nil(res.body['data'][1].updated_at)
        assert.not_nil(res.body['data'][1].username)
      end)
    end)

    describe("validate admins", function()
      it("requires unique consumer.username", function()
        local params = {
          username = admins[1].consumer.username,
          email = "unique@test.com",
        }

        local res, match, err = admins_helpers.validate(params, db, "POST")

        assert.is_nil(err)
        assert.same(admins[1], match)
        assert.is_false(res)
      end)

      it("requires unique admin.email", function()
        local params = {
          username = "i-am-unique",
          custom_id = "i-am-unique",
          email = "admin-2@test.com",
        }

        local res, match, err = admins_helpers.validate(params, db, "POST")

        assert.is_nil(err)
        assert.same(admins[2], match)
        assert.is_false(res)
      end)

      it("works on update as well as create", function()
        -- admin 1 can't have the same email as admin 2
        local params = {
          id = admins[1].id,
          username = admins[1].username,
          custom_id = admins[1].custom_id,
          email = admins[2].email,
        }

        local res, match, err = admins_helpers.validate(params, db, "PATCH")

        assert.is_nil(err)
        assert.same(admins[2], match)
        assert.is_false(res)
      end)
    end)

    describe("create", function()
      local snapshot

      before_each(function()
        snapshot = assert:snapshot()
      end)

      after_each(function()
        snapshot:revert()
      end)

      it("returns the data structure the API expects", function()
        local params = {
          username = "gruce1",
          email = "gruce1@KONGHQ.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }
        local opts = {
          token_optional = true,
          db = db,
        }

        local res = admins_helpers.create(params, opts)

        assert.same(200, res.code)

        -- these fields should match what was passed in
        local keys = {
          "status",
          "username",
          "custom_id",
        }

        for _, k in pairs(keys) do
          assert.same(params[k], res.body.admin[k])
        end

        -- email stored in lower case
        assert.same("gruce1@konghq.com", res.body.admin.email)

        -- these fields are auto-generated, should be present
        assert.not_nil(res.body.admin.id)
        assert.not_nil(res.body.admin.created_at)
        assert.not_nil(res.body.admin.updated_at)
      end)

      it("rejects the 'type' parameter", function()
        local opts = {
          token_optional = false,
          db = db,
        }

        local params = {
          username = "gruce1",
          email = "gruce1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
          type = enums.CONSUMERS.TYPE.ADMIN,
        }

        local res = admins_helpers.create(params, opts)
        local expected = {
          code = 400,
          body = { message = "Invalid parameter: 'type'" }
        }
        assert.same(expected, res)
      end)

      pending("it links existing admin to new workspace", function()
        -- need to refactor link_to_workspace. putting this test in as a
        -- placeholder to get it out of the admins routes spec
      end)

      it("returns 409 when rbac_user with same name already exists", function()
        -- rbac_user who is not part of an admin record
      end)

      it("returns API-friendly message when insert fails", function()
        stub(db.admins, "insert").returns(nil, "failed!")

        local opts = {
          token_optional = false,
          db = db,
        }

        local params = {
          username = "gruce-" .. utils.uuid(),
          email = "gruce-" .. utils.uuid() .. "@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local res = admins_helpers.create(params, opts)
        local expected = {
          code = 500,
          body = { message = "failed to create admin" }
        }
        assert.same(expected, res)
      end)
    end)

    describe("update", function()
      local admin

      setup(function()
        admin = assert(db.admins:insert(
          {
            username = "admin",
            custom_id = ngx.null,
            email = "admin@test.com",
            status = enums.CONSUMERS.TYPE.INVITED,
          })
        )
      end)
      teardown(function()
        if admin then
          db.admins:delete(admin)
        end
      end)

      it("doesn't fail when admin doesn't have a credential", function()
        local res, err = admins_helpers.update({ custom_id = "foo" }, admins[3], { db = db})
        assert.is_nil(err)

        -- should look just like admins[3], but with a custom_id
        -- and a different updated_at
        local expected = {
          custom_id = "foo",
          id = admins[3].id,
          username = admins[3].username,
          email = admins[3].email,
          status = admins[3].status,
          created_at = admins[3].created_at,
        }
        res.body.updated_at = nil

        assert.same({ code = 200, body = expected }, res)
      end)

      it("updates a null field to a non-null one", function()
        assert.is_nil(admin.custom_id)
        local new_custom_id = "admin-custom-id"
        local params = {
          id = admin.id,
          username = admin.username,
          custom_id = new_custom_id,
          email = admin.email,
        }

        local res, err = admins_helpers.update(params, admin, { db = db })
        assert.is_nil(err)
        assert.same(new_custom_id, res.body.custom_id)
      end)

      it("updates a non-null field to null", function()
        local params = {
          username = admin.username,
          custom_id = ngx.null,
          email = admin.email,
        }

        local res = admins_helpers.update(params, admin, { db = db })
        assert.same(nil, res.body.custom_id)
      end)

      it("keeps admin.username and basicauth_credentials.name in sync", function()
        -- create a credential to keep in sync
        assert(db.basicauth_credentials:insert({
          consumer = admin.consumer,
          username = admin.username,
          password = "password",
        }))

        local params = {
          id = admin.id,
          username = admin.username .. utils.uuid(),
        }

        local res, err = admins_helpers.update(params, admin, { db = db })
        assert.is_nil(err)
        assert.same(params.username, res.body.username)

        local creds, err = db.basicauth_credentials:page_for_consumer(admin.consumer)
        assert.is_nil(err)
        assert.same(params.username, creds[1].username)
      end)
    end)

    describe("delete", function()
      it("deletes an admin", function()
        local admin = assert(db.admins:insert({
          username = "deleteme" .. utils.uuid(),
          email = "deleteme@konghq.com",
          status = enums.CONSUMERS.STATUS.INVITED,
        }))

        local res, err = admins_helpers.delete(admin, { db = db })
        assert.is_nil(err)
        assert.same({ code = 204 }, res)

        local rbac_user = db.rbac_users:select({ id = admin.rbac_user.id })
        assert.is_nil(rbac_user)

        local consumer = db.consumers:select({ id = admin.consumer.id })
        assert.is_nil(consumer)
      end)
    end)

    describe("link_to_workspace", function()
      it("links an admin to another workspace", function()
        -- odd-numbered admins are in default_ws
        local linked, err = admins_helpers.link_to_workspace(admins[1], another_ws)

        assert.is_nil(err)
        assert.is_true(linked)

        local ws_list, err = workspaces.find_workspaces_by_entity({
          workspace_id = another_ws.id,
          entity_type = "consumers",
          entity_id = admins[1].consumer.id,
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
    end)
  end)
end
