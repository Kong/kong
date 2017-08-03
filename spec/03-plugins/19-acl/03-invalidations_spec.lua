local helpers = require "spec.helpers"

describe("Plugin: ACL (invalidations)", function()
  local admin_client, proxy_client
  local consumer1, acl1

  before_each(function()
    helpers.dao:truncate_tables()
    helpers.run_migrations()

    consumer1 = assert(helpers.dao.consumers:insert {
      username = "consumer1"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey123",
      consumer_id = consumer1.id
    })
    acl1 = assert(helpers.dao.acls:insert {
      group = "admin",
      consumer_id = consumer1.id
    })
    assert(helpers.dao.acls:insert {
      group = "pro",
      consumer_id = consumer1.id
    })

    local consumer2 = assert(helpers.dao.consumers:insert {
      username = "consumer2"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey124",
      consumer_id = consumer2.id
    })
    assert(helpers.dao.acls:insert {
      group = "admin",
      consumer_id = consumer2.id
    })

    local api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "acl1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api1.id,
      config = {
        whitelist = {"admin"}
      }
    })

    local api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "acl2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id
    })
    assert(helpers.dao.plugins:insert {
      name = "acl",
      api_id = api2.id,
      config = {
        whitelist = {"ya"}
      }
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    if admin_client and proxy_client then
      admin_client:close()
      proxy_client:close()
    end

    helpers.stop_kong()
  end)

  describe("ACL entity invalidation", function()
    before_each(function()
      helpers.run_migrations()
    end)

    it("should invalidate when ACL entity is deleted", function()
      -- It should work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(200, res)

      -- Check that the cache is populated

      local cache_key = helpers.dao.acls:cache_key(consumer1.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Delete ACL group (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/consumer1/acls/" .. acl1.id,
        headers = {}
      })
      assert.res_status(204, res)

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key,
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- It should not work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(403, res)
    end)
    it("should invalidate when ACL entity is updated", function()
      -- It should work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123&prova=scemo",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(200, res)

      -- It should not work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl2.com"
        }
      })
      assert.res_status(403, res)

      -- Check that the cache is populated
      local cache_key = helpers.dao.acls:cache_key(consumer1.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Update ACL group (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/consumers/consumer1/acls/" .. acl1.id,
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          group = "ya"
        }
      })
      assert.res_status(200, res)

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key,
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- It should not work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(403, res)

      -- It works now
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl2.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  describe("Consumer entity invalidation", function()
    before_each(function()
      helpers.run_migrations()
    end)

    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(200, res)

      -- Check that the cache is populated
      local cache_key = helpers.dao.acls:cache_key(consumer1.id)
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/" .. cache_key,
        headers = {}
      })
      assert.res_status(200, res)

      -- Delete Consumer (which triggers invalidation)
      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/consumer1",
        headers = {}
      })
      assert.res_status(204, res)

      -- Wait for cache to be invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key,
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- Wait for key to be invalidated
      local keyauth_cache_key = helpers.dao.keyauth_credentials:cache_key("apikey123")
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. keyauth_cache_key,
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- It should not work
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200?apikey=apikey123",
        headers = {
          ["Host"] = "acl1.com"
        }
      })
      assert.res_status(403, res)
    end)
  end)

end)
