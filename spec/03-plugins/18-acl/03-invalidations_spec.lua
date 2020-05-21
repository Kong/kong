local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: ACL (invalidations) [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local consumer
    local acl
    local db

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "acls",
        "keyauth_credentials",
      })

      consumer = bp.consumers:insert {
        username = "consumer1"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey123",
        consumer = { id = consumer.id },
      }

      acl = bp.acls:insert {
        group    = "admin",
        consumer = { id = consumer.id },
      }

      bp.acls:insert {
        group    = "pro",
        consumer = { id = consumer.id },
      }

      local consumer2 = bp.consumers:insert {
        username = "consumer2"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey124",
        consumer = { id = consumer2.id },
      }

      bp.acls:insert {
        group    = "admin",
        consumer = { id = consumer2.id },
      }

      local route1 = bp.routes:insert {
        hosts = { "acl1.com" },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id }
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route1.id },
        config   = {
          whitelist = {"admin"}
        }
      }

      local route2 = bp.routes:insert {
        hosts = { "acl2.com" },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id }
      }

      bp.plugins:insert {
        name     = "acl",
        route = { id = route2.id },
        config   = {
          whitelist = { "ya" }
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
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
      it("should invalidate when ACL entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(200, res)

        -- Check that the cache is populated

        local cache_key = db.acls:cache_key(consumer.id)
        local res = assert(admin_client:get("/cache/" .. cache_key, {
          headers = {}
        }))
        assert.res_status(200, res)

        -- Delete ACL group (which triggers invalidation)
        local res = assert(admin_client:delete("/consumers/consumer1/acls/" .. acl.id, {
          headers = {}
        }))
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_for_invalidation(cache_key)

        -- It should not work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(403, res)
      end)
      it("should invalidate when ACL entity is updated", function()
        -- It should work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123&prova=scemo", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(200, res)

        -- It should not work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl2.com"
          }
        }))
        assert.res_status(403, res)

        -- Check that the cache is populated
        local cache_key = db.acls:cache_key(consumer.id)
        local res = assert(admin_client:get("/cache/" .. cache_key, {
          headers = {}
        }))
        assert.res_status(200, res)

        -- Update ACL group (which triggers invalidation)
        local res = assert(admin_client:patch("/consumers/consumer1/acls/" .. acl.id, {
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            group            = "ya"
          }
        }))
        assert.res_status(200, res)

        -- Wait for cache to be invalidated
        helpers.wait_for_invalidation(cache_key)

        -- It should not work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(403, res)

        -- It works now
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl2.com"
          }
        }))
        assert.res_status(200, res)
      end)
    end)

    describe("Consumer entity invalidation", function()
      it("should invalidate when Consumer entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(200, res)

        -- Check that the cache is populated
        local cache_key = db.acls:cache_key(consumer.id)
        local res = assert(admin_client:get("/cache/" .. cache_key, {
          headers = {}
        }))
        assert.res_status(200, res)

        -- Delete Consumer (which triggers invalidation)
        local res = assert(admin_client:delete("/consumers/consumer1", {
          headers = {}
        }))
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_for_invalidation(cache_key)

        -- Wait for key to be invalidated
        local keyauth_cache_key = db.keyauth_credentials:cache_key("apikey123")
        helpers.wait_for_invalidation(keyauth_cache_key)

        -- It should not work
        local res = assert(proxy_client:get("/status/200?apikey=apikey123", {
          headers = {
            ["Host"] = "acl1.com"
          }
        }))
        assert.res_status(401, res)
      end)
    end)
  end)
end
