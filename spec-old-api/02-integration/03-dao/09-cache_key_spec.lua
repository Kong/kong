local helpers = require "spec.helpers"

describe("<dao>:cache_key()", function()
  describe("generates unique cache keys for core entities", function()
<<<<<<< HEAD
    local workspace_id = ngx.ctx.workspaces[1].id

    it("(Consumers)", function()
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

      local cache_key = helpers.dao.consumers:cache_key(consumer_id)
      assert.equal("consumers:" .. consumer_id .. ":::::" .. workspace_id, cache_key)
    end)

||||||| merged common ancestors
    it("(Consumers)", function()
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

      local cache_key = helpers.dao.consumers:cache_key(consumer_id)
      assert.equal("consumers:" .. consumer_id .. "::::", cache_key)
    end)

=======
>>>>>>> 0.15.0
    it("(Plugins)", function()
      local name        = "my-plugin"
      local api_id      = "7c46b5f8-3430-11e7-afec-784f437104fa"
      local consumer_id = "59c7fb5e-3430-11e7-b51f-784f437104fa"

<<<<<<< HEAD
      local cache_key = helpers.dao.plugins:cache_key(name)
      assert.equal("plugins:" .. name .. ":::::" .. workspace_id, cache_key)
||||||| merged common ancestors
      local cache_key = helpers.dao.plugins:cache_key(name)
      assert.equal("plugins:" .. name .. "::::", cache_key)
=======
      local cache_key = helpers.db.plugins:cache_key(name)
      assert.equal("plugins:" .. name .. "::::", cache_key)
>>>>>>> 0.15.0

<<<<<<< HEAD
      cache_key = helpers.dao.plugins:cache_key(name, api_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. "::::" .. workspace_id, cache_key)
||||||| merged common ancestors
      cache_key = helpers.dao.plugins:cache_key(name, api_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. ":::", cache_key)
=======
      cache_key = helpers.db.plugins:cache_key({ name = name, api = { id = api_id }})
      assert.equal("plugins:" .. name .. "::::" .. api_id, cache_key)
>>>>>>> 0.15.0

<<<<<<< HEAD
      cache_key = helpers.dao.plugins:cache_key(name, api_id, consumer_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. ":" .. consumer_id .. ":::" .. workspace_id,
||||||| merged common ancestors
      cache_key = helpers.dao.plugins:cache_key(name, api_id, consumer_id)
      assert.equal("plugins:" .. name .. ":" .. api_id .. ":" .. consumer_id .. "::",
=======
      cache_key = helpers.db.plugins:cache_key({ name = name, api = { id = api_id }, consumer = { id = consumer_id }})
      assert.equal("plugins:" .. name .. ":::" .. consumer_id .. ":" .. api_id,
>>>>>>> 0.15.0
                   cache_key)

<<<<<<< HEAD
      cache_key = helpers.dao.plugins:cache_key(name, nil, consumer_id)
      assert.equal("plugins:" .. name .. "::" .. consumer_id .. ":::" .. workspace_id, cache_key)
||||||| merged common ancestors
      cache_key = helpers.dao.plugins:cache_key(name, nil, consumer_id)
      assert.equal("plugins:" .. name .. "::" .. consumer_id .. "::", cache_key)
=======
      cache_key = helpers.db.plugins:cache_key({ name = name, consumer = { id = consumer_id }})
      assert.equal("plugins:" .. name .. ":::" .. consumer_id .. ":", cache_key)
>>>>>>> 0.15.0
    end)
  end)
end)
