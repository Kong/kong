local hybrid_helper = require "spec.hybrid"
local cjson   = require "cjson"


hybrid_helper.run_for_each_deploy({}, function(helpers, strategy, deploy, rpc, rpc_sync)
  describe("Plugin: key-auth (invalidations) [" .. helpers.format_tags() .. "]", function()
    local admin_client, proxy_client
    local db

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local route = bp.routes:insert {
        hosts = { "key-auth.test" },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route.id },
      }

      local consumer = bp.consumers:insert {
        username = "bob",
      }

      bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
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

    it("invalidates credentials when the Consumer is deleted", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.keyauth_credentials:cache_key("kong")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        assert.res_status(200, res)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      -- delete Consumer entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob"
      })
      assert.res_status(204, res)

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("kong")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidates credentials from cache when deleted", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      local credential_id
      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.keyauth_credentials:cache_key("kong")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.id

      else
        res = assert(admin_client:send {
          method = "GET",
          path   = "/consumers/bob/key-auth"
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.data[1].id
      end

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob/key-auth/" .. credential_id
      })
      assert.res_status(204, res)

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("kong")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidated credentials from cache when updated", function()
      -- populate cache
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      local credential_id
      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.keyauth_credentials:cache_key("kong")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.id

      else
        res = assert(admin_client:send {
          method = "GET",
          path   = "/consumers/bob/key-auth"
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.data[1].id
      end

      -- delete credential entity
      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/consumers/bob/key-auth/" .. credential_id,
        body    = {
          key   = "kong-updated"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("kong")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth.test",
          ["apikey"] = "kong-updated"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end)
