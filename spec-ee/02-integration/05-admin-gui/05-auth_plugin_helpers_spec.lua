-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants           = require "kong.constants"
local helpers             = require "spec.helpers"
local ee_api              = require "kong.enterprise_edition.api_helpers"
local auth_plugin_helpers = require "kong.enterprise_edition.auth_plugin_helpers"

local db

local ADMIN_CONSUMER_USERNAME_SUFFIX = constants.ADMIN_CONSUMER_USERNAME_SUFFIX

local function retrieve_consumer(db, id, options)
  return db.consumers:select({ id = id }, options or {})
end

for _, strategy in helpers.each_strategy() do
  local function truncate_tables()
    db:truncate("consumers")
    db:truncate("rbac_user_roles")
    db:truncate("rbac_roles")
    db:truncate("rbac_users")
    db:truncate("admins")
  end

  describe("auth plugin helpers with #" .. strategy, function()
    local default_ws

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy)

      truncate_tables()

      default_ws = assert(db.workspaces:select_by_name("default"))

      ngx.ctx.workspace = default_ws.id
    end)

    lazy_teardown(function()
      truncate_tables()
    end)

    describe("validate_admin_and_attach_ctx()", function()
      before_each(function()
        truncate_tables()
      end)

      it("attach workspaces from cache's consumer well when show_ws_id is false", function()
        local stub_validate_admin = stub(ee_api, "validate_admin")
        local stub_attach = stub(ee_api, "attach_consumer_and_workspaces")
        local username = "not_exists@email.com"
        local self = {}
        local admin = db.admins:select_by_username(
          username,
          { skip_rbac = true }
        )

        assert.is_nil(admin)

        assert(auth_plugin_helpers.validate_admin_and_attach_ctx(
          self,
          false,
          username,
          nil,
          true,
          true,
          true
        ))

        admin = db.admins:select_by_username(
          username,
          { skip_rbac = true }
        )
        local consumer_id = admin.consumer.id

        -- Begining doesn't have consumer in cache
        local cache_key = db.consumers:cache_key(consumer_id)
        local cache_consumer = kong.cache:get(cache_key, nil, retrieve_consumer, db, consumer_id)
        assert.is_not_nil(cache_consumer)
        assert.is_nil(cache_consumer.ws_id)

        -- after load from db and validate the consumer
        cache_consumer = kong.cache:get(cache_key, nil, retrieve_consumer, db, consumer_id)
        assert.is_not_nil(cache_consumer)
        assert.is_nil(cache_consumer.ws_id)

        assert.same(username, admin.username)
        assert(ee_api.attach_workspaces(self, consumer_id))
        assert.is_not_nil(self.workspaces)
        assert.same(default_ws.id, self.workspaces[1].id)

        -- after attache workspace validate the consumer
        cache_consumer = kong.cache:get(cache_key, nil, retrieve_consumer, db, consumer_id)
        assert.is_not_nil(cache_consumer)
        assert.is_not_nil(cache_consumer.ws_id)

        stub_validate_admin:revert()
        stub_attach:revert()
      end)

      it("attach workspaces from cache's consumer well when show_ws_id is true", function()
        local stub_validate_admin = stub(ee_api, "validate_admin")
        local stub_attach = stub(ee_api, "attach_consumer_and_workspaces")
        local username = "not_exists@email.com"
        local self = {}
        local admin = db.admins:select_by_username(
          username,
          { skip_rbac = true }
        )

        assert.is_nil(admin)

        assert(auth_plugin_helpers.validate_admin_and_attach_ctx(
          self,
          false,
          username,
          nil,
          true,
          true,
          true
        ))

        admin = db.admins:select_by_username(
          username,
          { skip_rbac = true }
        )
        local consumer_id = admin.consumer.id

        -- Begining doesn't have consumer in cache
        local cache_key = db.consumers:cache_key(consumer_id)
        local cache_consumer = kong.cache:get(cache_key, nil, retrieve_consumer, db, consumer_id, { show_ws_id = true })
        assert.is_not_nil(cache_consumer)
        assert.is_not_nil(cache_consumer.ws_id)

        assert.same(username, admin.username)
        assert(ee_api.attach_workspaces(self, consumer_id))
        assert.is_not_nil(self.workspaces)
        assert.same(default_ws.id, self.workspaces[1].id)

        -- after attache workspace validate the consumer
        cache_consumer = kong.cache:get(cache_key, nil, retrieve_consumer, db, consumer_id)
        assert.is_not_nil(cache_consumer)
        assert.is_not_nil(cache_consumer.ws_id)

        stub_validate_admin:revert()
        stub_attach:revert()
      end)

      it("creates admin if not exists", function()
        local stub_validate_admin = stub(ee_api, "validate_admin")
        local stub_attach = stub(ee_api, "attach_consumer_and_workspaces")

        local self = {}
        local username = "not_exists@email.com"

        local admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.is_nil(admin)

        assert(auth_plugin_helpers.validate_admin_and_attach_ctx(
          self,
          false,
          username,
          nil,
          true,
          true,
          true
        ))

        admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.same(username, admin.username)

        assert.stub(ee_api.attach_consumer_and_workspaces).was.called_with(
          self,
          admin.consumer.id
        )

        assert.same(
          username .. ADMIN_CONSUMER_USERNAME_SUFFIX,
          ngx.ctx.authenticated_consumer.username
        )

        assert.same(
          admin.consumer.id,
          ngx.ctx.authenticated_credential.consumer_id
        )

        assert.same(true, admin.rbac_token_enabled)

        stub_validate_admin:revert()
        stub_attach:revert()
      end)

      it("creates admin with rbac token disabled", function()
        local stub_validate_admin = stub(ee_api, "validate_admin")
        local stub_attach = stub(ee_api, "attach_consumer_and_workspaces")

        local self = {}
        local username = "not_exists@email.com"

        local admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.is_nil(admin)

        assert(auth_plugin_helpers.validate_admin_and_attach_ctx(
          self,
          false,
          username,
          nil,
          true,
          true,
          false
        ))

        admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.same(username, admin.username)

        assert.stub(ee_api.attach_consumer_and_workspaces).was.called_with(
          self,
          admin.consumer.id
        )

        assert.same(
          username .. ADMIN_CONSUMER_USERNAME_SUFFIX,
          ngx.ctx.authenticated_consumer.username
        )

        assert.same(
          admin.consumer.id,
          ngx.ctx.authenticated_credential.consumer_id
        )

        assert.same(false, admin.rbac_token_enabled)

        stub_validate_admin:revert()
        stub_attach:revert()
      end)

      it("Do not create admin when auto admin create is false", function()
        local stub_validate_admin = stub(ee_api, "validate_admin")
        local stub_attach = stub(ee_api, "attach_consumer_and_workspaces")
        local stub_auth_fail = stub(auth_plugin_helpers,"no_admin_error")
        -- local stub_admin = stub(auth_plugin_helpers,"validate_admin_and_attach_ctx")
        -- local mock = (stub_auth_fail,true)

        local self = {}
        local username = "not_exists@email.com"

        local admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.is_nil(admin)

        assert.stub(auth_plugin_helpers.validate_admin_and_attach_ctx(
          self,
          false,
          username,
          nil,
          false,
          true,
          false
        ))

        admin = db.admins:select_by_username(
          username,
          {skip_rbac = true}
        )

        assert.is_nil(admin)

        stub_validate_admin:revert()
        stub_attach:revert()
        stub_auth_fail:revert()
      end)

    end)
  end)
end