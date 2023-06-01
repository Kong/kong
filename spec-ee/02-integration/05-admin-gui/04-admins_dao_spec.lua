-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local constants  = require "kong.constants"

local enums      = require "kong.enterprise_edition.dao.enums"

local ADMIN_CONSUMER_USERNAME_SUFFIX = constants.ADMIN_CONSUMER_USERNAME_SUFFIX

for _, strategy in helpers.each_strategy() do
  local db, admins, _

  local function truncate_tables()
    db:truncate("consumers")
    db:truncate("rbac_user_roles")
    db:truncate("rbac_roles")
    db:truncate("rbac_users")
    db:truncate("admins")
  end

  describe("admins dao with #" .. strategy, function()

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy)

      kong.db = db
      admins = db.admins

      -- consumers are workspaceable, so we need a workspace context
      -- TODO: do admins need to be workspaceable? Preferably not.
      local default_ws = assert(db.workspaces:select_by_name("default"))
      ngx.ctx.workspace = default_ws.id
    end)

    lazy_teardown(function()
      truncate_tables()
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
          username = "Admin-1",
          custom_id = "admin-1-custom-id",
          email = "admin-1@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.is_table(admin)
        assert.same(admin_params.email, admin.email)
        assert.same(admin_params.username, admin.username)
        assert.same(admin_params.username:lower(), admin.username_lower)
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

      it("sets consumer username and custom_id according to admin's", function()
        local admin_params = {
          username = "admin-2",
          custom_id = "admin-2-custom-id",
          email = "admin-2@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local admin, err = admins:insert(admin_params)
        assert.is_nil(err)
        assert.same(admin.username .. ADMIN_CONSUMER_USERNAME_SUFFIX, admin.consumer.username)
        assert.same(admin.username_lower .. ADMIN_CONSUMER_USERNAME_SUFFIX:lower(), admin.consumer.username_lower)
        assert.same(admin.custom_id, admin.consumer.custom_id)
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
        assert.same(admin.username .. ADMIN_CONSUMER_USERNAME_SUFFIX, admin.consumer.username)
        assert.not_same(admin.username, admin.rbac_user.name)
      end)

      it("validates user input - invalid fields", function()
        -- "user" is not a valid field
        local admin_params = {
          user = "admin-1",
          username = "admin-user",
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

      it("validates user input - username is required", function()
        local admin_params = {
          custom_id = "admin-no-username",
          email = "admin-no-username@konghq.com",
          status = enums.CONSUMERS.STATUS.APPROVED,
        }

        local _, err, err_t = admins:insert(admin_params)
        local expected_t = {
          code = 2,
          fields = {
            username = "required field missing",
          },
          message = "schema violation (username: required field missing)",
          name = "schema violation",
          strategy = strategy,
        }
        assert.same(expected_t, err_t)

        assert.same("[" .. strategy .. "] schema violation (username: required field missing)", err)
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
        assert.same(nil, kong.db.consumers:select_by_username("gruce"))
        assert.same(nil, kong.db.rbac_users:select_by_name("gruce"))
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
        assert.same(nil, kong.db.consumers:select_by_username("gruce"))
        assert.same(nil, kong.db.rbac_users:select_by_name("gruce"))
      end)
    end)

    describe("username_lower", function()
      it("admins:insert() sets username_lower", function()
        assert(kong.db.admins:insert {
          username = "INSERT@kong.com",
        })
        local admin, err
        admin, err = kong.db.admins:select_by_username("INSERT@kong.com")
        assert.is_nil(err)
        assert(admin.username == "INSERT@kong.com")
        assert(admin.username_lower == "insert@kong.com")
      end)

      it("admins:update() sets username_lower", function()
        assert(kong.db.admins:insert {
          username = "KING@kong.com",
        })
        local admin, err
        admin, err = kong.db.admins:select_by_username("KING@kong.com")
        assert.is_nil(err)
        assert(admin.username == "KING@kong.com")
        assert(admin.username_lower == "king@kong.com")
        assert(kong.db.admins:update({ id = admin.id }, { username = "KINGDOM@kong.com" }))
        admin, err = kong.db.admins:select({ id = admin.id })
        assert.is_nil(err)
        assert(admin.username == "KINGDOM@kong.com")
        assert(admin.username_lower == "kingdom@kong.com")
      end)

      it("admins:update_by_username() sets username_lower", function()
        assert(kong.db.admins:insert {
          username = "ANOTHER@kong.com",
        })
        local admin, err
        admin, err = kong.db.admins:select_by_username("ANOTHER@kong.com")
        assert.is_nil(err)
        assert(admin.username == "ANOTHER@kong.com")
        assert(admin.username_lower == "another@kong.com")
        assert(kong.db.admins:update_by_username("ANOTHER@kong.com", { username = "YANOTHER@kong.com" }))
        admin, err = kong.db.admins:select({ id = admin.id })
        assert.is_nil(err)
        assert(admin.username == "YANOTHER@kong.com")
        assert(admin.username_lower == "yanother@kong.com")
      end)

      it("admins:update_by_email() sets username_lower", function()
        assert(kong.db.admins:insert {
          email = "ANOTHER_by_email@kong.com",
          username = "ANOTHER_by_email@kong.com",
        })
        local admin, err
        admin, err = kong.db.admins:select_by_username("ANOTHER_by_email@kong.com")
        assert.is_nil(err)
        assert(admin.username == "ANOTHER_by_email@kong.com")
        assert(admin.username_lower == "another_by_email@kong.com")
        assert(kong.db.admins:update_by_email("ANOTHER_by_email@kong.com", { username = "YANOTHER_by_email@kong.com" }))
        admin, err = kong.db.admins:select({ id = admin.id })
        assert.is_nil(err)
        assert(admin.username == "YANOTHER_by_email@kong.com")
        assert(admin.username_lower == "yanother_by_email@kong.com")
      end)

      it("admins:update_by_custom_id() sets username_lower", function()
        assert(kong.db.admins:insert {
          custom_id = "ANOTHER_by_custom_id@kong.com",
          username = "ANOTHER_by_custom_id@kong.com",
        })
        local admin, err
        admin, err = kong.db.admins:select_by_username("ANOTHER_by_custom_id@kong.com")
        assert.is_nil(err)
        assert(admin.username == "ANOTHER_by_custom_id@kong.com")
        assert(admin.username_lower == "another_by_custom_id@kong.com")
        assert(kong.db.admins:update_by_custom_id("ANOTHER_by_custom_id@kong.com", { username = "YANOTHER_by_custom_id@kong.com" }))
        admin, err = kong.db.admins:select({ id = admin.id })
        assert.is_nil(err)
        assert(admin.username == "YANOTHER_by_custom_id@kong.com")
        assert(admin.username_lower == "yanother_by_custom_id@kong.com")
      end)

      it("admins:insert() doesn't allow username_lower values", function()
        local admin, err, err_t = kong.db.admins:insert({
          email = "heyo@admin.com",
          username = "HEYO",
          username_lower = "heyo"
        })
        assert.is_nil(admin)
        assert(err)
        assert.same('auto-generated field cannot be set by user', err_t.fields.username_lower)
      end)

      it("admins:update() doesn't allow username_lower values", function()
        local admin = kong.db.admins:insert({
          email = "update@admin.com",
          username = "update",
          custom_id = "update",
        })
        assert(admin)
        local updated, err, err_t = kong.db.admins:update({ id = admin.id }, {
          username = "HEYO",
          username_lower = "heyo"
        })
        assert.is_nil(updated)
        assert(err)
        assert.same(err_t.fields.username_lower, 'auto-generated field cannot be set by user')
      end)

      it("admins:update_by_username() doesn't allow username_lower values", function()
        local updated, err, err_t = kong.db.admins:update_by_username("update", {
          username_lower = "heyo"
        })
        assert.is_nil(updated)
        assert(err)
        assert.same(err_t.fields.username_lower, 'auto-generated field cannot be set by user')
      end)

      it("admins:update_by_email() doesn't allow username_lower values", function()
        local updated, err, err_t = kong.db.admins:update_by_email("update@admin.com", {
          username_lower = "heyo"
        })
        assert.is_nil(updated)
        assert(err)
        assert.same(err_t.fields.username_lower, 'auto-generated field cannot be set by user')
      end)

      it("admins:update_by_custom_id() doesn't allow username_lower values", function()
        local updated, err, err_t = kong.db.admins:update_by_custom_id("update", {
          username_lower = "heyo"
        })
        assert.is_nil(updated)
        assert(err)
        assert.same(err_t.fields.username_lower, 'auto-generated field cannot be set by user')
      end)

      it("admins:select_by_username_ignore_case() ignores username case", function()
        assert(kong.db.admins:insert {
          username = "GRUCEO@kong.com",
          custom_id = "12345",
        })
        local admins, err = kong.db.admins:select_by_username_ignore_case("gruceo@kong.com")
        assert.is_nil(err)
        assert(#admins == 1)
        assert.same("GRUCEO@kong.com", admins[1].username)
        assert.same("12345", admins[1].custom_id)
      end)

      it("admins:select_by_username_ignore_case() sorts oldest created_at first", function()
        assert(kong.db.admins:insert {
          username = "gruceO@kong.com",
          custom_id = "23456",
        })

        assert(kong.db.admins:insert {
          username = "GruceO@kong.com",
          custom_id = "34567",
        })

        local admins, err = kong.db.admins:select_by_username_ignore_case("Gruceo@kong.com")
        assert.is_nil(err)
        assert(#admins == 3)
        assert(admins[1].created_at <= admins[2].created_at)
        assert(admins[2].created_at <= admins[3].created_at)
      end)
    end)
  end)
end
