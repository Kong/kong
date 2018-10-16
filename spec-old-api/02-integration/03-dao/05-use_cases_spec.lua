local Factory = require "kong.dao.factory"
local DB = require "kong.db"

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Real use-cases with DB: #" .. strategy, function()
    local bp, db, dao
    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      dao:truncate_table("apis")
      db:truncate("plugins")
      db:truncate("consumers")
    end)

    it("retrieves plugins for plugins_iterator", function()
      local api, err = dao.apis:insert {
        name = "example",
        hosts = { "example.com" },
        upstream_url = "http://example.com",
      }
      assert.falsy(err)

      local consumer, err = bp.consumers:insert {username = "bob"}
      assert.falsy(err)

      local key_auth, err = bp.plugins:insert {
        name = "key-auth", api = { id = api.id }
      }
      assert.falsy(err)

      local rate_limiting_for_api, err = bp.plugins:insert {
        name = "rate-limiting", api = { id = api.id },
        config = {minute = 1}
      }
      assert.falsy(err)

      local rate_limiting_for_consumer, err = bp.plugins:insert {
        name = "rate-limiting", api = { id = api.id }, consumer = { id = consumer.id },
        config = {minute = 1}
      }
      assert.falsy(err)

      -- Retrieval
      local key = db.plugins:cache_key("key-auth", nil, nil, nil, api.id)
      local row, err = db.plugins:select_by_cache_key(key)
      assert.falsy(err)
      assert.same(key_auth, row)

      --
      key = db.plugins:cache_key("rate-limiting", nil, nil, nil, api.id)
      row, err = db.plugins:select_by_cache_key(key)
      assert.falsy(err)
      assert.same(rate_limiting_for_api, row)

      --
      key = db.plugins:cache_key("rate-limiting", nil, nil, consumer.id, api.id)
      row, err = db.plugins:select_by_cache_key(key)
      assert.falsy(err)
      assert.same(rate_limiting_for_consumer, row)
    end)

    it("update a plugin config", function()
      local api, err = dao.apis:insert {
        name         = "example",
        hosts        = { "example.com" },
        upstream_url = "http://example.com",
      }
      assert.falsy(err)

      local key_auth, err = bp.plugins:insert {
        name = "key-auth", api = { id = api.id },
      }
      assert.falsy(err)

      local updated_key_auth, err = db.plugins:update({ id = key_auth.id }, {
        config = {key_names = {"key-updated"}}
      })
      assert.falsy(err)
      assert.same({"key-updated"}, updated_key_auth.config.key_names)
    end)

    it("does not override plugin config if partial update", function()
      local api, err = dao.apis:insert {
        name         = "example",
        hosts        = { "example.com" },
        upstream_url = "http://example.com",
      }
      assert.falsy(err)

      local key_auth, err = bp.plugins:insert {
        name = "key-auth", api = { id = api.id },
        config = {
          hide_credentials = true
        }
      }
      assert.falsy(err)

      local updated_key_auth, err = db.plugins:update({ id = key_auth.id }, {
        config = {key_names = {"key-set-null-test-updated"}}
      })
      assert.falsy(err)
      assert.same({"key-set-null-test-updated"}, updated_key_auth.config.key_names)
      assert.True(updated_key_auth.config.hide_credentials)
    end)
  end)
end


describe("#cassandra", function()
  describe("LB policy", function()
    it("accepts DCAwareRoundRobin", function()
      local helpers = require "spec.helpers"

      local kong_config                = helpers.test_conf

      local database                   = kong_config.database
      local cassandra_lb_policy        = kong_config.cassandra_lb_policy
      local cassandra_local_datacenter = kong_config.cassandra_local_datacenter

      finally(function()
        kong_config.database                   = database
        kong_config.cassandra_lb_policy        = cassandra_lb_policy
        kong_config.cassandra_local_datacenter = cassandra_local_datacenter
      end)

      kong_config.database                   = "cassandra"
      kong_config.cassandra_lb_policy        = "DCAwareRoundRobin"
      kong_config.cassandra_local_datacenter = "my-dc"

      local db = DB.new(kong_config)
      assert(db:init_connector())
      assert(Factory.new(kong_config, db))
    end)
  end)
end)
