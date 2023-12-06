-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Plugin: key-auth-enc (invalidations) [#" .. strategy .. "]", function()
    local admin_client, proxy_client
    local db

    local credential

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_enc_credentials",
      }, { "key-auth-enc" })

      local route = bp.routes:insert {
        hosts = { "key-auth-enc.test" },
      }

      bp.plugins:insert {
        name     = "key-auth-enc",
        route = { id = route.id },
      }

      local consumer = bp.consumers:insert {
        username = "bob",
      }

      credential = bp.keyauth_enc_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      assert(helpers.start_kong({
        database   = strategy ~= "off" and strategy or nil,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled,key-auth-enc",
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
          ["Host"]   = "key-auth-enc.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_enc_credentials:key_ident_cache_key({ key = "kong" })
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      assert.res_status(200, res)

      -- delete Consumer entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob"
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth-enc.test",
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
          ["Host"]   = "key-auth-enc.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_enc_credentials:key_ident_cache_key({ key = "kong" })
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      assert.res_status(200, res)

      -- delete credential entity
      res = assert(admin_client:send {
        method = "DELETE",
        path   = "/consumers/bob/key-auth-enc/" .. credential.id
      })
      assert.res_status(204, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method  = "GET",
          path    = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth-enc.test",
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
          ["Host"]   = "key-auth-enc.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is populated
      local cache_key = db.keyauth_enc_credentials:key_ident_cache_key({ key = "kong" })
      res = assert(admin_client:send {
        method = "GET",
        path   = "/cache/" .. cache_key
      })
      assert.res_status(200, res)

      -- delete credential entity
      res = assert(admin_client:send {
        method  = "PATCH",
        path    = "/consumers/bob/key-auth-enc/" .. credential.id,
        body    = {
          key   = "kong-updated"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(200, res)

      -- ensure cache is invalidated
      helpers.wait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/cache/" .. cache_key
        })
        res:read_body()
        return res.status == 404
      end)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth-enc.test",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(401, res)

      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["Host"]   = "key-auth-enc.test",
          ["apikey"] = "kong-updated"
        }
      })
      assert.res_status(200, res)
    end)
  end)
end
