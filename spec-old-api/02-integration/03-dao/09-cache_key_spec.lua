local helpers = require "spec.helpers"

describe("<dao>:cache_key()", function()
  describe("generates unique cache keys for core entities", function()
    it("(Plugins)", function()
      local name        = "my-plugin"
      local api_id      = "7c46b5f8-3430-11e7-afec-784f437104fa"
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

      local cache_key = helpers.dao.plugins:cache_key(name)
      assert.equal("plugins:" .. name .. "::::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, api_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. ":::", cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, api_id, consumer_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. ":" .. consumer_id .. "::",
                   cache_key)

      cache_key = helpers.dao.plugins:cache_key(name, nil, consumer_id)
      assert.equal("plugins:" .. name .. "::" .. consumer_id .. "::", cache_key)
    end)
  end)
end)
