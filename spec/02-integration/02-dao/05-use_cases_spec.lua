local helpers = require "spec.02-integration.02-dao.helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_config)
  describe("Real use-cases with DB: #"..kong_config.database, function()
    local factory
    setup(function()
      factory = assert(Factory.new(kong_config))
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    it("retrieves plugins for plugins_iterator", function()
      local api, err = factory.apis:insert {
        name = "mockbin", hosts = { "mockbin.com" },
        upstream_url = "http://mockbin.com"
      }
      assert.falsy(err)

      local consumer, err = factory.consumers:insert {username = "bob"}
      assert.falsy(err)

      local key_auth, err = factory.plugins:insert {
        name = "key-auth", api_id = api.id
      }
      assert.falsy(err)

      local _, err = factory.plugins:insert {
        name = "rate-limiting", api_id = api.id,
        config = {minute = 1}
      }
      assert.falsy(err)

      local rate_limiting_for_consumer, err = factory.plugins:insert {
        name = "rate-limiting", api_id = api.id, consumer_id = consumer.id,
        config = {minute = 1}
      }
      assert.falsy(err)

      -- Retrieval
      local rows, err = factory.plugins:find_all {
        name = "key-auth",
        api_id = api.id
      }
      assert.falsy(err)
      assert.equal(1, #rows)
      assert.same(key_auth, rows[1])

      --
      rows, err = factory.plugins:find_all {
        name = "rate-limiting",
        api_id = api.id
      }
      assert.falsy(err)
      assert.equal(2, #rows)

      --
      rows, err = factory.plugins:find_all {
        name = "rate-limiting",
        api_id = api.id,
        consumer_id = consumer.id
      }
      assert.falsy(err)
      assert.equal(1, #rows)
      assert.same(rate_limiting_for_consumer, rows[1])
    end)

    it("update a plugin config", function()
      local api, err = factory.apis:insert {
        name = "mockbin", hosts = { "mockbin.com" },
        upstream_url = "http://mockbin.com"
      }
      assert.falsy(err)

      local key_auth, err = factory.plugins:insert {
        name = "key-auth", api_id = api.id
      }
      assert.falsy(err)

      local updated_key_auth, err = factory.plugins:update({
        config = {key_names = {"key-updated"}}
      }, key_auth)
      assert.falsy(err)
      assert.same({"key-updated"}, updated_key_auth.config.key_names)
    end)

    it("does not override plugin config if partial update", function()
      local api, err = factory.apis:insert {
        name = "mockbin", hosts = { "mockbin.com" },
        upstream_url = "http://mockbin.com"
      }
      assert.falsy(err)

      local key_auth, err = factory.plugins:insert {
        name = "key-auth", api_id = api.id,
        config = {
          hide_credentials = true
        }
      }
      assert.falsy(err)

      local updated_key_auth, err = factory.plugins:update({
        config = {key_names = {"key-set-null-test-updated"}}
      }, key_auth)
      assert.falsy(err)
      assert.same({"key-set-null-test-updated"}, updated_key_auth.config.key_names)
      assert.True(updated_key_auth.config.hide_credentials)
    end)
  end)
end)


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

      assert(Factory.new(kong_config))
    end)
  end)
end)
