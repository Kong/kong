local spec_helpers = require "spec.helpers"
local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local helpers = require "spec.02-integration.03-dao.helpers"
local Factory = require "kong.dao.factory"
local enums = require "kong.enterprise_edition.dao.enums"
local DB = require "kong.db"

helpers.for_each_dao(function(kong_config)
  local db, factory, admins

  local function truncate_tables()
    db:truncate("workspace_entities")
    db:truncate("consumers")
    db:truncate("rbac_user_roles")
    db:truncate("rbac_roles")
    db:truncate("rbac_users")
    db:truncate("admins")
  end

  describe("admins dao with #" .. kong_config.database, function()

    lazy_setup(function()
      db = DB.new(kong_config)
      assert(db:init_connector())

      spec_helpers.bootstrap_database(db)

      factory = assert(Factory.new(kong_config, db))
      assert(factory:init())
      admins = db.admins

      singletons.db = db
      singletons.dao = factory

      -- consumers are workspaceable, so we need a workspace context
      -- TODO: do admins need to be workspaceable? Preferably not.
      ngx.ctx.workspaces = {
        workspaces.fetch_workspace("default")
      }
    end)

    lazy_teardown(function()
      truncate_tables()
      ngx.shared.kong_cassandra:flush_expired()
    end)

    describe("insert()", function()
      local snapshot

      before_each(function()
        truncate_tables()
        snapshot = assert:snapshot()
      end)

      after_each(function()
        snapshot:revert()
      end)

      it("inserts a valid admin", function()
        local admin_params = {
          username = "admin-1",
          custom_id = "admin-1-custom-id",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.is_table(admin)
        assert.same(admin_params.email, admin.email)
        assert.same(admin_params.status, admin.status)
        assert.not_nil(admin.consumer)
        assert.not_nil(admin.rbac_user)
      end)

      it("defaults to INVITED", function()
        local admin_params = {
          username = "admin-1",
          custom_id = "admin-1-custom-id",
          email = "admin-1@konghq.com",
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.is_table(admin)
        assert.same(enums.CONSUMERS.STATUS.INVITED, admin.status)
      end)

      it("generates unique consumer.username and rbac_user.name", function()
        -- we aren't keeping these in sync with admin name, so they need
        -- to be unique. That way if you create an admin 'kinman' and change
        -- the name to 'karen' and back to 'kinman' you don't get a warning
        -- that 'kinman' already exists.
        local admin_params = {
          username = "admin-1",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.not_same(admin.username, admin.consumer.username)
        assert.not_same(admin.username, admin.rbac_user.name)

        local admin_params = {
          custom_id = "admin-2-custom_id",
          email = "admin-2@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.not_same(admin.custom_id, admin.consumer.custom_id)
        assert.not_same(admin.custom_id, admin.rbac_user.name)
      end)

      it("rolls back the rbac_user if we can't create the consumer", function()
        stub(db.consumers, "insert").returns(nil, "failed!")

        local admin_params = {
          username = "admin-1",
          custom_id = "admin-1-custom-id",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local _, err = admins:insert(admin_params)
        assert.same(err, "failed!")

        -- leave no trace
        local consumers = assert(#workspaces.compat_find_all("consumers", { username = "gruce"}))
        assert.same(0, consumers)

        local rbac_users = assert(#workspaces.compat_find_all("rbac_users", { name = "gruce" }))
        assert.same(0, rbac_users)
      end)

      it("rolls back the rbac_user and consumer if we can't create the admin", function()
        stub(db.admins, "insert").returns(nil, "failed!")

        local admin_params = {
          username = "admin-1",
          custom_id = "admin-1-custom-id",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local _, err = admins:insert(admin_params)
        assert.same(err, "failed!")

        -- leave no trace
        local consumers = assert(#workspaces.compat_find_all("consumers", { username = "gruce"}))
        assert.same(0, consumers)

        local rbac_users = assert(#workspaces.compat_find_all("rbac_users", { name = "gruce" }))
        assert.same(0, rbac_users)
      end)
    end)
  end)
end)
