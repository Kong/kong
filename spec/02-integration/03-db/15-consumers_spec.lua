-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers          = require "spec.helpers"
local singletons       = require "kong.singletons"
local workspace_config = require "kong.portal.workspace_config"
local constants        = require "kong.constants"

local null             = ngx.null
local ws_constants     = constants.WORKSPACE_CONFIG

-- Note: include "off" strategy here as well
for _, strategy in helpers.all_strategies() do
  describe("db.consumers #" .. strategy, function()
    local bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "consumers",
      })
      _G.kong.db = db

      assert(bp.consumers:insert {
        username = "GRUCEO@kong.com",
        custom_id = "12345",
        created_at = 1,
      })
    end)

    lazy_teardown(function()
      db.consumers:truncate()
    end)

    it("consumers:insert() sets username_lower", function()
      local consumer, err = kong.db.consumers:select_by_username("GRUCEO@kong.com")
      assert.is_nil(err)
      assert(consumer.username == "GRUCEO@kong.com")
      assert(consumer.username_lower == "gruceo@kong.com")
    end)

    it("consumers:update() sets username_lower", function()
      assert(bp.consumers:insert {
        username = "KING@kong.com",
      })
      local consumer, err
      consumer, err = kong.db.consumers:select_by_username("KING@kong.com")
      assert.is_nil(err)
      assert(consumer.username == "KING@kong.com")
      assert(consumer.username_lower == "king@kong.com")
      assert(bp.consumers:update({ id = consumer.id }, { username = "KINGDOM@kong.com" }))
      consumer, err = kong.db.consumers:select({ id = consumer.id })
      assert.is_nil(err)
      assert(consumer.username == "KINGDOM@kong.com")
      assert(consumer.username_lower == "kingdom@kong.com")
    end)

    it("consumers:update_by_username() sets username_lower", function()
      assert(bp.consumers:insert {
        username = "ANOTHER@kong.com",
      })
      local consumer, err
      consumer, err = kong.db.consumers:select_by_username("ANOTHER@kong.com")
      assert.is_nil(err)
      assert(consumer.username == "ANOTHER@kong.com")
      assert(consumer.username_lower == "another@kong.com")
      assert(kong.db.consumers:update_by_username("ANOTHER@kong.com", { username = "YANOTHER@kong.com" }))
      consumer, err = kong.db.consumers:select({ id = consumer.id })
      assert.is_nil(err)
      assert(consumer.username == "YANOTHER@kong.com")
      assert(consumer.username_lower == "yanother@kong.com")
    end)

    it("consumers:upsert() sets username_lower", function()
      assert(bp.consumers:upsert({ id = "4e8d95d4-40f2-4818-adcb-30e00c349618"}, {
        username = "Absurd@kong.com"
      }))
      local consumer, err = kong.db.consumers:select_by_username("Absurd@kong.com")
      assert.is_nil(err)
      assert(consumer.username == "Absurd@kong.com")
      assert(consumer.username_lower == "absurd@kong.com")
    end)

    it("consumers:insert() doesn't allow username_lower values", function()
      local consumer, err, err_t = kong.db.consumers:insert({
        custom_id = "insert654321",
        username_lower = "heyo"
      })
      assert.is_nil(consumer)
      assert(err)
      assert.same('auto-generated field cannot be set by user', err_t.fields.username_lower)
    end)

    it("consumers:update() doesn't allow username_lower values", function()
      local consumer = kong.db.consumers:insert({
        custom_id = "update654321",
      })
      assert(consumer)
      local updated, err, err_t = kong.db.consumers:update({ id = consumer.id }, {
        username = "HEYO",
        username_lower = "heyo"
      })
      assert.is_nil(updated)
      assert(err)
      assert.same('auto-generated field cannot be set by user', err_t.fields.username_lower)
    end)

    it("consumers:update_by_username() doesn't allow username_lower values", function()
      local consumer = kong.db.consumers:insert({
        username = "update_by_username654321",
      })
      assert(consumer)
      local updated, err, err_t = kong.db.consumers:update_by_username("update_by_username654321", {
        username_lower = "heyo"
      })
      assert.is_nil(updated)
      assert(err)
      assert.same('auto-generated field cannot be set by user', err_t.fields.username_lower)
    end)

    it("consumers:upsert() doesn't allow username_lower values", function()
      local consumer, err, err_t = kong.db.consumers:upsert({ id = "deadbeef-beef-beef-beef-deaddeadbeef" }, {
        username = "upsert654321",
        username_lower = "upsert654321",
      })
      assert.is_nil(consumer)
      assert(err)
      assert.same('auto-generated field cannot be set by user', err_t.fields.username_lower)
    end)

    it("consumers:update() should set username_lower to null if username is null", function()
      local consumer = kong.db.consumers:insert({
        username = "Kongsumer1",
        custom_id = "custom_id1"
      })
      assert(consumer.username)
      assert(consumer.username_lower)
      assert(consumer)
      local updated, err, err_t = kong.db.consumers:update({ id = consumer.id }, {
        username = null
      })
      assert(updated)
      assert.is_nil(err)
      assert.is_nil(err_t)
      assert.is_nil(updated.username)
      assert.is_nil(updated.username_lower)
    end)

    it("consumers:update_by_username() should set username_lower to null if username is null", function()
      local consumer = kong.db.consumers:insert({
        username = "Kongsumer2",
        custom_id = "custom_id2"
      })
      assert(consumer.username)
      assert(consumer.username_lower)
      assert(consumer)
      local updated, err, err_t = kong.db.consumers:update_by_username(consumer.username, {
        username = null
      })
      assert(updated)
      assert.is_nil(err)
      assert.is_nil(err_t)
      assert.is_nil(updated.username)
      assert.is_nil(updated.username_lower)
    end)

    it("consumer username_lower conflicts if by_username_ignore_case", function()
      local consumer = kong.db.consumers:insert({
        username = "KonGSumeR",
      })
      assert(consumer)

      local consumer_to_update = kong.db.consumers:insert({
        username = "KONGSUMER_TO_UPDATE",
      })
      assert(consumer_to_update)

      -- should conflict when admin openid-connect + by_username_ignore_case = true
      local temp_config = singletons.configuration
      singletons.configuration = {
        admin_gui_auth = "openid-connect",
        admin_gui_auth_conf = { by_username_ignore_case = true },
      }

      local consumer, err, err_t = kong.db.consumers:insert({
        username = "Kongsumer",
      })
      assert.is_nil(consumer)
      assert(err)
      assert(err_t)
      assert.same([[UNIQUE violation detected on '{username_lower="kongsumer"}']], err_t.message)

      -- but should not conflict with own row
      local updated, err, err_t = kong.db.consumers:update({ id = consumer_to_update.id }, {
        username = "Kongsumer_To_Update"
      })
      assert.is_nil(err)
      assert.is_nil(err_t)
      assert(updated)

      singletons.configuration = temp_config

      -- should not conflict when admin openid-connect + by_username_ignore_case = false
      local temp_config = singletons.configuration
      singletons.configuration = {
        admin_gui_auth = "openid-connect",
        admin_gui_auth_conf = { by_username_ignore_case = false },
      }

      local consumer, err, err_t = kong.db.consumers:insert({
        username = "KongSumer",
      })
      assert(consumer)
      assert.is_nil(err)
      assert.is_nil(err_t)

      singletons.configuration = temp_config

      -- should conflict when portal openid-connect + by_username_ignore_case = true
      local temp_ws_config_retrieve = workspace_config.retrieve
      workspace_config.retrieve = function(key)
        if key == ws_constants.PORTAL_AUTH then
          return "openid-connect"
        elseif key == ws_constants.PORTAL_AUTH_CONF then
          return [[{"by_username_ignore_case": true}]]
        end
      end
      local consumer, err, err_t = kong.db.consumers:insert({
        username = "Kongsumer",
      })
      assert.is_nil(consumer)
      assert(err)
      assert(err_t)
      assert.same([[UNIQUE violation detected on '{username_lower="kongsumer"}']], err_t.message)

      -- but should not conflict with own row
      local updated, err, err_t = kong.db.consumers:update({ id = consumer_to_update.id }, {
        username = "Kongsumer_to_update"
      })
      assert(updated)
      assert.is_nil(err)
      assert.is_nil(err_t)

      workspace_config.retrieve = temp_ws_config_retrieve

      -- should not conflict when portal openid-connect + by_username_ignore_case = false
      local temp_ws_config_retrieve = workspace_config.retrieve
      workspace_config.retrieve = function(key)
        if key == ws_constants.PORTAL_AUTH then
          return "openid-connect"
        elseif key == ws_constants.PORTAL_AUTH_CONF then
          return [[{"by_username_ignore_case": false}]]
        end
      end
      local consumer, err, err_t = kong.db.consumers:insert({
        username = "Kongsumer",
      })
      assert(consumer)
      assert.is_nil(err)
      assert.is_nil(err_t)

      workspace_config.retrieve = temp_ws_config_retrieve

      -- should not conflict if neither portal or admin use openid-connect
      local consumer, err, err_t = kong.db.consumers:insert({
        username = "KongsumeR",
      })
      assert(consumer)
      assert.is_nil(err_t)
      assert.is_nil(err)

    end)

    it("consumers:select_by_username_ignore_case() ignores username case", function() 
      local consumers, err = kong.db.consumers:select_by_username_ignore_case("gruceo@kong.com")
      assert.is_nil(err)
      assert(#consumers == 1)
      assert.same("GRUCEO@kong.com", consumers[1].username)
      assert.same("12345", consumers[1].custom_id)
    end)

    it("consumers:select_by_username_ignore_case() sorts oldest created_at first", function() 
      assert(bp.consumers:insert {
        username = "gruceO@kong.com",
        custom_id = "23456",
        created_at = 2
      })

      assert(bp.consumers:insert {
        username = "GruceO@kong.com",
        custom_id = "34567",
        created_at = 3
      })

      local consumers, err = kong.db.consumers:select_by_username_ignore_case("Gruceo@kong.com")
      assert.is_nil(err)
      assert(#consumers == 3)
      assert.same("GRUCEO@kong.com", consumers[1].username)
      assert.same("gruceO@kong.com", consumers[2].username)
      assert.same("GruceO@kong.com", consumers[3].username)
    end)
  end)
end

