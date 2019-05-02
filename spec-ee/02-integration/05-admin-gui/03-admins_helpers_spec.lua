local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local enums = require "kong.enterprise_edition.dao.enums"
local admins_helpers = require "kong.enterprise_edition.admins_helpers"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"

local cache = {
  get = function(self, x, y, f, ...) return f(...) end,
}
for _, strategy in helpers.each_strategy() do

  describe("admin_helpers with #" .. strategy, function()
    local db, factory
    local default_ws, another_ws
    local admins = {}

    lazy_setup(function()
      _, db, factory = helpers.get_db_utils(strategy)

      if _G.kong then
        _G.kong.db = db
        _G.kong.cache =  cache
      else
        _G.kong = { db = db,
          cache = cache
        }
      end

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

    before_each(function()
      -- default to default workspace. ;-) each test can override
      ngx.ctx.workspaces = { default_ws }
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
        assert.same(200, res.code)
        assert(utils.is_array(res.body.data))
        assert.same(2, #res.body.data)
        assert.same(ngx.null, res.body.next)

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

        local res, match, err = admins_helpers.validate(params, db)

        assert.is_nil(err)
        assert.same(admins[1], match)
        assert.is_false(res)
      end)

      it("requires unique admin.email", function()
        local params = {
          username = "i-am-unique",
          custom_id = "i-am-unique",
          email = "admin-3@test.com",
        }

        local res, match, err = admins_helpers.validate(params, db)

        assert.is_nil(err)
        assert.same(admins[3], match)
        assert.is_false(res)
      end)

      it("works on update as well as create", function()
        -- admin 1 can't have the same email as admin 3
        local params = {
          username = admins[1].username,
          custom_id = admins[1].custom_id,
          email = admins[3].email,
        }

        local res, match, err = admins_helpers.validate(params, db, admins[1])

        assert.is_nil(err)
        assert.same(admins[3], match)
        assert.is_false(res)
      end)

      it("works across workspaces", function()
        -- admin 1 (default_ws) can't have the same email as admin 2 (another_ws)
        local params = {
          username = admins[1].username,
          custom_id = admins[1].custom_id,
          email = admins[2].email,
        }

        local res, match, err = admins_helpers.validate(params, db, admins[1])

        assert.is_nil(err)
        assert.same(admins[2], match)
        assert.is_false(res)
      end)

      it("allows update of self", function()
        -- update admin 1
        local params = {
          username = admins[1].username .. "-updated",
          custom_id = admins[1].custom_id,
          email = admins[1].email,
        }

        local res, match, err = admins_helpers.validate(params, db, admins[1])

        assert.is_nil(err)
        assert.is_nil(match)
        assert.is_true(res)
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
        assert.is_nil(res.body.message)
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

      it("it links existing admin to new workspace", function()
        local opts = {
          token_optional = true,
          db = db,
          workspace = default_ws,
        }

        local params = {
          username = admins[2].username,
          email = admins[2].email,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local res = admins_helpers.create(params, opts)
        assert.same(200, res.code)
        assert.same(admins_helpers.transmogrify(admins[2]), res.body.admin)
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

      it("doesn't 500 when email is null", function()
        local opts = {
          token_optional = false,
          db = db,
        }

        local params = {
          username = "gruce-" .. utils.uuid(),
          email = ngx.null,
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local res = admins_helpers.create(params, opts)
        assert.same(200, res.code)
      end)
    end)

    describe("update", function()
      local admin

      lazy_setup(function()
        admin = assert(db.admins:insert(
          {
            username = "admin",
            custom_id = ngx.null,
            email = "admin@test.com",
            status = enums.CONSUMERS.TYPE.INVITED,
          })
        )
      end)
      lazy_teardown(function()
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

      it("keeps username for admin, consumer, and credential in sync", function()
        -- create a credential to keep in sync
        assert(db.basicauth_credentials:insert({
          consumer = admin.consumer,
          username = admin.username,
          password = "password",
        }))

        local params = {
          username = admin.username .. utils.uuid(),
        }

        local res = assert(admins_helpers.update(params, admin, { db = db }))
        assert.same(params.username, res.body.username)

        local creds = assert(db.basicauth_credentials:page_for_consumer(admin.consumer))
        assert.same(params.username, creds[1].username)

        local consumers = assert(db.admins:page_for_consumer(admin.consumer))
        assert.same(params.username, consumers[1].username)
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

    describe("find_by_username_or_id", function()
      it("finds by username", function()
        local res, err = admins_helpers.find_by_username_or_id(admins[1].username)
        assert.is_nil(err)

        assert.same(admins[1].username, res.username)
        assert.same(admins[1].custom_id, res.custom_id)
        assert.same(admins[1].status, res.status)
        assert.same(admins[1].email, res.email)
        assert.not_nil(res.created_at)
        assert.not_nil(res.updated_at)
        assert.is_nil(res.consumer)
        assert.is_nil(res.rbac_user)
      end)

      it("finds by id", function()
        local res, err = admins_helpers.find_by_username_or_id(admins[1].id)
        assert.is_nil(err)

        assert.same(admins[1].username, res.username)
      end)

      it("renders the raw entity when asked", function()
        local res, err = admins_helpers.find_by_username_or_id(admins[1].username, true)
        assert.is_nil(err)

        assert.same(admins[1].username, res.username)
        assert.same(admins[1].custom_id, res.custom_id)
        assert.same(admins[1].status, res.status)
        assert.same(admins[1].email, res.email)
        assert.not_nil(res.created_at)
        assert.not_nil(res.updated_at)
        assert.same(admins[1].consumer.id, res.consumer.id)
        assert.same(admins[1].rbac_user.id, res.rbac_user.id)
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

    describe("workspaces_for_admin", function()
      it("returns workspaces", function()
        local opts = {
          db = db,
        }
        local res, err = admins_helpers.workspaces_for_admin(admins[1].username, opts)
        assert.is_nil(err)
        assert.same(200, res.code)
        assert.same(2, #res.body)

        -- ensure that what came back looks like a workspace
        local ws = res.body[1]
        for _, key in ipairs({ "config", "created_at", "id", "meta", "name" }) do
          assert.not_nil(ws[key])
        end
      end)
    end)
  end)
end
