local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("use-cases with DB: #" .. strategy, function()
    local bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "keyauth_credentials",
      })
    end)

    it("retrieves plugins for plugins_iterator", function()
      -- fixtures

      local service = bp.services:insert()
      local consumer = bp.consumers:insert()

      -- insert plugin for Service

      local key_auth, err = db.plugins:insert {
        name    = "key-auth",
        service = { id = service.id },
      }
      assert.is_nil(err)

      -- insert plugin for Service (bis)

      local rate_limiting_for_service, err = db.plugins:insert {
        name    = "rate-limiting",
        service = { id = service.id },
        config  = { minute = 1 },
      }
      assert.is_nil(err)

      -- insert plugin for Service + Consumer

      local rate_limiting_for_consumer, err = db.plugins:insert {
        name     = "rate-limiting",
        service  = { id = service.id },
        consumer = { id = consumer.id },
        config   = { minute = 1 },
      }
      assert.is_nil(err)

      -- TEST 1: retrieve key-auth plugin for Service

      local key = db.plugins:cache_key("key-auth", nil, service.id, nil, nil)
      local row, err = db.plugins:select_by_cache_key(key)
      assert.is_nil(err)
      assert.same(key_auth, row)

      -- TEST 2: retrieve rate-limiting plugin for Service

      key = db.plugins:cache_key("rate-limiting", nil, service.id, nil, nil)
      row, err = db.plugins:select_by_cache_key(key)
      assert.is_nil(err)
      assert.same(rate_limiting_for_service, row)

      -- TEST 3: retrieve rate-limiting plugin for Service + Consumer

      key = db.plugins:cache_key("rate-limiting", nil, service.id, consumer.id, nil)
      row, err = db.plugins:select_by_cache_key(key)
      assert.is_nil(err)
      assert.same(rate_limiting_for_consumer, row)
    end)

    it("update a plugin config", function()
      local service = bp.services:insert()

      local key_auth, err = db.plugins:insert {
        name    = "key-auth",
        service = { id = service.id },
      }
      assert.is_nil(err)

      local pk = { id = key_auth.id }
      local updated_key_auth, err = db.plugins:update(pk, {
        config = { key_names = { "key-updated" } }
      })
      assert.is_nil(err)
      assert.same({ "key-updated" }, updated_key_auth.config.key_names)
    end)

    it("does not override plugin config if partial update", function()
      local service = bp.services:insert()

      local key_auth, err = db.plugins:insert {
        name = "key-auth",
        service = { id = service.id },
        config = {
          hide_credentials = true,
        }
      }
      assert.is_nil(err)

      local pk = { id = key_auth.id }
      local updated_key_auth, err = db.plugins:update(pk, {
        config = { key_names = { "key-set-null-test-updated" } }
      })
      assert.is_nil(err)
      assert.same({ "key-set-null-test-updated" }, updated_key_auth.config.key_names)
      assert.is_true(updated_key_auth.config.hide_credentials)
    end)
  end)
end
