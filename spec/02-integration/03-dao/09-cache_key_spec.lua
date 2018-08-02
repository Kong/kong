local helpers = require "spec.helpers"

describe("<dao>:cache_key()", function()
  describe("generates unique cache keys for core entities", function()
    it("(Consumers)", function()
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

      -- raw string is a backwards-compatible alternative for entities
      -- with an `id` as their primary key
      local cache_key = helpers.db.consumers:cache_key(consumer_id)
      assert.equal("consumers:" .. consumer_id .. "::::", cache_key)

      -- primary key in table form works the same
      cache_key = helpers.db.consumers:cache_key({ id = consumer_id })
      assert.equal("consumers:" .. consumer_id .. "::::", cache_key)
    end)

    it("(Plugins)", function()
      local name        = "my-plugin"
      local route_id    = "db81fe58-bf43-11e7-8e5c-784f437104fa"
      local service_id  = "7c46b5f8-3430-11e7-afec-784f437104fa"
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

      local cache_key = helpers.dao.plugins:cache_key(name)
      assert.equal("plugins:" .. name .. "::::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, route_id)
      assert.equal("plugins:" .. name .. ":" .. route_id .. ":::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, route_id, service_id)
      assert.equal("plugins:" .. name .. ":" .. route_id .. ":" ..
                   service_id .. "::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, route_id, service_id, consumer_id)
      assert.equal("plugins:" .. name .. ":" .. route_id .. ":" ..
                   service_id .. ":" .. consumer_id .. ":", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, nil, service_id)
      assert.equal("plugins:" .. name .. "::" .. service_id .. "::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, nil, nil, consumer_id)
      assert.equal("plugins:" .. name .. ":::" .. consumer_id .. ":", cache_key)
    end)
  end)
end)
