local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

for conf, database in helpers.for_each_db() do
  describe("Real use-cases with DB: #" .. database, function()
    local factory
    setup(function()
      factory = assert(Factory.new(conf))
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    it("retrieves plugins for plugins_iterator", function()
      local api = assert(factory.apis:insert {
        name = "mockbin", request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      })

      local consumer = assert(factory.consumers:insert {username = "bob"})

      local key_auth = assert(factory.plugins:insert {
        name = "key-auth", api_id = api.id
      })

      assert(factory.plugins:insert {
        name = "rate-limiting", api_id = api.id,
        config = {minute = 1}
      })

      local rate_limiting_for_consumer = assert(factory.plugins:insert {
        name = "rate-limiting", api_id = api.id, consumer_id = consumer.id,
        config = {minute = 1}
      })

      -- Retrieval
      local rows = assert(factory.plugins:find_all {
        name = "key-auth",
        api_id = api.id
      })
      assert.equal(1, #rows)
      assert.same(key_auth, rows[1])

      rows = assert(factory.plugins:find_all {
        name = "rate-limiting",
        api_id = api.id
      })
      assert.equal(2, #rows)

      rows = assert(factory.plugins:find_all {
        name = "rate-limiting",
        api_id = api.id,
        consumer_id = consumer.id
      })
      assert.equal(1, #rows)
      assert.same(rate_limiting_for_consumer, rows[1])
    end)

    it("update a plugin config", function()
      local api = assert(factory.apis:insert {
        name = "mockbin", request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      })

      local key_auth = assert(factory.plugins:insert {
        name = "key-auth", api_id = api.id
      })

      local updated_key_auth = assert(factory.plugins:update({
        config = {key_names = {"key_updated"}}
      }, key_auth))
      assert.same({"key_updated"}, updated_key_auth.config.key_names)
    end)

    it("does not override plugin config if partial update", function()
      local api = assert(factory.apis:insert {
        name = "mockbin", request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      })

      local key_auth = assert(factory.plugins:insert {
        name = "key-auth", api_id = api.id,
        config = {
          hide_credentials = true
        }
      })

      local updated_key_auth = assert(factory.plugins:update({
        config = {key_names = {"key_set_null_test_updated"}}
      }, key_auth))
      assert.same({"key_set_null_test_updated"}, updated_key_auth.config.key_names)
      assert.True(updated_key_auth.config.hide_credentials)
    end)
  end)
end
