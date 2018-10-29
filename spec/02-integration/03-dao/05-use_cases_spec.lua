local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("use-cases with DB: #" .. strategy, function()
    local dao
    local bp

    setup(function()
      local _
      bp, _, dao = helpers.get_db_utils(strategy)
    end)

    it("retrieves plugins for plugins_iterator", function()
      -- fixtures

      local service = bp.services:insert()
      local consumer = bp.consumers:insert()

      -- insert plugin for Service

      local key_auth, err = dao.plugins:insert {
        name       = "key-auth",
        service_id = service.id,
      }
      assert.is_nil(err)

      -- insert plugin for Service (bis)

      local _, err = dao.plugins:insert {
        name       = "rate-limiting",
        service_id = service.id,
        config     = { minute = 1 },
      }
      assert.is_nil(err)

      -- insert plugin for Service + Consumer

      local rate_limiting_for_consumer, err = dao.plugins:insert {
        name        = "rate-limiting",
        service_id  = service.id,
        consumer_id = consumer.id,
        config      = { minute = 1 },
      }
      assert.is_nil(err)

      -- TEST 1: retrieve key-auth plugin for Service

      local rows, err = dao.plugins:find_all {
        name       = "key-auth",
        service_id = service.id,
      }
      assert.is_nil(err)
      assert.equal(1, #rows)
      assert.same(key_auth, rows[1])

      -- TEST 2: retrieve rate-limiting plugin for Service
      -- note: this is correct according to the legacy DAO behavior, but
      -- note that the second rate-limiting plugin also has a consumer_id,
      -- and hence, should only run when this Consumer is authenticated.

      rows, err = dao.plugins:find_all {
        name       = "rate-limiting",
        service_id = service.id,
      }
      assert.is_nil(err)
      assert.equal(2, #rows)

      -- TEST 3: retrieve rate-limiting plugin for Service + Consumer

      rows, err = dao.plugins:find_all {
        name        = "rate-limiting",
        service_id  = service.id,
        consumer_id = consumer.id
      }
      assert.is_nil(err)
      assert.equal(1, #rows)
      assert.same(rate_limiting_for_consumer, rows[1])
    end)

    it("update a plugin config", function()
      local service = bp.services:insert()

      local key_auth, err = dao.plugins:insert {
        name       = "key-auth",
        service_id = service.id,
      }
      assert.is_nil(err)

      local updated_key_auth, err = dao.plugins:update({
        config = { key_names = { "key-updated" } }
      }, key_auth)
      assert.is_nil(err)
      assert.same({ "key-updated" }, updated_key_auth.config.key_names)
    end)

    it("does not override plugin config if partial update", function()
      local service = bp.services:insert()

      local key_auth, err = dao.plugins:insert {
        name = "key-auth",
        service_id = service.id,
        config = {
          hide_credentials = true,
        }
      }
      assert.is_nil(err)

      local updated_key_auth, err = dao.plugins:update({
        config = { key_names = { "key-set-null-test-updated" } }
      }, key_auth)
      assert.is_nil(err)
      assert.same({ "key-set-null-test-updated" }, updated_key_auth.config.key_names)
      assert.is_true(updated_key_auth.config.hide_credentials)
    end)
  end)
end
