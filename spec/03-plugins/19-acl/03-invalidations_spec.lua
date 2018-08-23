local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: ACL (invalidations) [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local consumer
    local acl
    local dao
    local db

    before_each(function()
      local bp
      bp, db, dao = helpers.get_db_utils(strategy)

      consumer = bp.consumers:insert {
        username = "consumer1"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey123",
        consumer = { id = consumer.id },
      }

      acl = bp.acls:insert {
        group       = "admin",
        consumer_id = consumer.id
      }

      bp.acls:insert {
        group       = "pro",
        consumer_id = consumer.id
      }

      local consumer2 = bp.consumers:insert {
        username = "consumer2"
      }

      bp.keyauth_credentials:insert {
        key      = "apikey124",
        consumer = { id = consumer2.id },
      }

      bp.acls:insert {
        group       = "admin",
        consumer_id = consumer2.id
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
      before_each(function()
        assert(dao:run_migrations())
      end)

      it("should invalidate when ACL entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(200, res)

        -- Check that the cache is populated

        local cache_key = dao.acls:cache_key(consumer.id)
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key,
          headers = {}
        })
        assert.res_status(200, res)

        -- Delete ACL group (which triggers invalidation)
        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/consumer1/acls/" .. acl.id,
          headers = {}
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key,
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- It should not work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(403, res)
      end)
      it("should invalidate when ACL entity is updated", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123&prova=scemo",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(200, res)

        -- It should not work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl2.com"
          }
        })
        assert.res_status(403, res)

        -- Check that the cache is populated
        local cache_key = dao.acls:cache_key(consumer.id)
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key,
          headers = {}
        })
        assert.res_status(200, res)

        -- Update ACL group (which triggers invalidation)
        local res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/consumers/consumer1/acls/" .. acl.id,
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            group            = "ya"
          }
        })
        assert.res_status(200, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key,
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- It should not work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(403, res)

        -- It works now
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl2.com"
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("Consumer entity invalidation", function()
      before_each(function()
        assert(dao:run_migrations())
      end)

      it("should invalidate when Consumer entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(200, res)

        -- Check that the cache is populated
        local cache_key = dao.acls:cache_key(consumer.id)
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key,
          headers = {}
        })
        assert.res_status(200, res)

        -- Delete Consumer (which triggers invalidation)
        local res = assert(admin_client:send {
          method  = "DELETE",
          path    = "/consumers/consumer1",
          headers = {}
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key,
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Wait for key to be invalidated
        local keyauth_cache_key = db.keyauth_credentials:cache_key("apikey123")
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. keyauth_cache_key,
            headers = {}
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- It should not work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=apikey123",
          headers = {
            ["Host"] = "acl1.com"
          }
        })
        assert.res_status(403, res)
      end)
    end)
  end)
end
