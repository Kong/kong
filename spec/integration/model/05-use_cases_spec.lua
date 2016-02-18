local inspect = require "inspect"

local utils = require "kong.tools.utils"
local helpers = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(db_type, default_options, TYPES)
  describe("Real use-cases with DB: #"..db_type, function()
    local factory
    setup(function()
      factory = Factory(db_type, default_options)
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    it("retrieves plugins for plugins_iterator", function()
      local api, err = factory.apis:insert {
        name = "mockbin", request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }
      assert.falsy(err)

      local consumer, err = factory.consumers:insert {username = "bob"}
      assert.falsy(err)

      local key_auth, err = factory.plugins:insert {
        name = "key-auth", api_id = api.id
      }
      assert.falsy(err)

      local rate_limiting_for_api, err = factory.plugins:insert {
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
  end)
end)
