local hybrid_helper = require "spec.hybrid"
local admin_api = require "spec.fixtures.admin_api"
local cjson = require "cjson"

hybrid_helper.run_for_each_deploy({ }, function(helpers, strategy, deploy, rpc, rpc_sync)
  describe("Plugin: basic-auth (invalidations) [" .. helpers.format_tags() .. "]", function()
    local admin_client
    local proxy_client
    local db

    lazy_setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "consumers",
        "plugins",
        "basicauth_credentials",
      })

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    after_each(function()
      if admin_client and proxy_client then
        admin_client:close()
        proxy_client:close()
      end
    end)

    local route
    local plugin
    local consumer
    local credential

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      if not route then
        route = admin_api.routes:insert {
          hosts = { "basic-auth.test" },
        }
      end

      if not plugin then
        plugin = admin_api.plugins:insert {
          name = "basic-auth",
          route = { id = route.id },
        }
      end

      if not consumer then
        consumer = admin_api.consumers:insert {
          username = "bob",
        }
      end

      if not credential then
        credential = admin_api.basicauth_credentials:insert {
          username = "bob",
          password = "kong",
          consumer = { id = consumer.id },
        }
      end

      helpers.wait_for_all_config_update()
    end)

    it("#invalidates credentials when the Consumer is deleted", function()
      local res
      helpers.pwait_until(function()
        -- populate cache
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth.test"
          }
        })
        assert.res_status(200, res)
      end)

      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.basicauth_credentials:cache_key("bob")
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
      consumer = nil
      credential = nil

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("bob")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.test"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidates credentials from cache when deleted", function()
      local res
      helpers.pwait_until(function()
        -- populate cache
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth.test"
          }
        })
        assert.res_status(200, res)
      end)

      local credential_id
      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.basicauth_credentials:cache_key("bob")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        local body = assert.res_status(200, res)
        local cred = cjson.decode(body)
        credential_id = cred.id

      else
        res = assert(admin_client:send {
          method = "GET",
          path   = "/consumers/bob/basic-auth"
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.data[1].id
      end

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob/basic-auth/" .. credential_id
      })
      assert.res_status(204, res)
      credential = nil

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("bob")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.test"
        }
      })
      assert.res_status(401, res)
    end)

    it("invalidated credentials from cache when updated", function()
      local res
      helpers.pwait_until(function()
        -- populate cache
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth.test"
          }
        })
        assert.res_status(200, res)
      end)

      local credential_id
      if deploy == "traditional" then
        -- ensure cache is populated, /cache endpoint only available in traditional mode
        local cache_key = db.basicauth_credentials:cache_key("bob")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key
        })
        local body = assert.res_status(200, res)
        local cred = cjson.decode(body)
        credential_id = cred.id

      else
        res = assert(admin_client:send {
          method = "GET",
          path   = "/consumers/bob/basic-auth"
        })
        local body = assert.res_status(200, res)
        local credential = cjson.decode(body)
        credential_id = credential.data[1].id
      end

      -- delete credential entity
      res = assert(admin_client:send {
        method     = "PATCH",
        path       = "/consumers/bob/basic-auth/" .. credential_id,
        body       = {
          username = "bob",
          password = "kong-updated"
        },
        headers    = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)
      credential = nil

      if deploy == "traditional" then
        -- ensure cache is invalidated
        local cache_key = db.keyauth_credentials:cache_key("bob")
        helpers.wait_for_invalidation(cache_key)

      else
        -- ensure config is up to date
        helpers.wait_for_all_config_update()
      end

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"]          = "basic-auth.test"
        }
      })
      assert.res_status(401, res)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmctdXBkYXRlZA==",
          ["Host"]          = "basic-auth.test"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end)
