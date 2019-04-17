local helpers = require "spec.helpers"
local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local enums = require "kong.enterprise_edition.dao.enums"


for _, strategy in helpers.each_strategy() do
  local db, dao, admins, _

  local function truncate_tables()
    db:truncate("workspace_entities")
    db:truncate("consumers")
    db:truncate("rbac_user_roles")
    db:truncate("rbac_roles")
    db:truncate("rbac_users")
    db:truncate("admins")
  end

  describe("admins dao with #" .. strategy, function()

    lazy_setup(function()
      _, db, dao = helpers.get_db_utils(strategy)

      singletons.db = db
      singletons.dao = dao
      admins = db.admins

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

      it("generates unique rbac_user.name", function()
        -- we aren't keeping this in sync with admin name, so it needs
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
        assert.same(admin.username, admin.consumer.username)
        assert.not_same(admin.username, admin.rbac_user.name)
      end)

      it("validates user input", function()
        -- "user" is not a valid field
        local admin_params = {
          user = "admin-1",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local _, err, err_t = admins:insert(admin_params)
        local expected_t = {
          code = 2,
          fields = {
            user = "unknown field"
          },
          message = "schema violation (user: unknown field)",
          name = "schema violation",
          strategy = strategy,
        }
        assert.same(expected_t, err_t)

        local expected_m = "[" .. strategy .. "] schema violation (user: unknown field)"
        assert.same(expected_m, err)
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
        local consumers = assert(#kong.db.consumers:select_all({ username = "gruce" }))
        assert.same(0, consumers)

        local rbac_users = assert(#kong.db.rbac_users:select_all({ name = "gruce" }))
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
        local consumers = assert(#kong.db.consumers:select_all({ username = "gruce" }))
        assert.same(0, consumers)

        local rbac_users = assert(#kong.db.rbac_users:select_all({ name = "gruce" }))
        assert.same(0, rbac_users)
      end)
    end)
  end)
end
