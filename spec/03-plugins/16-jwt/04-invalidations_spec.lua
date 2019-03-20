local helpers     = require "spec.helpers"
local cjson       = require "cjson"
local jwt_encoder = require "kong.plugins.jwt.jwt_parser"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: jwt (invalidations) [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local kongsumer
    local route
    local db

    before_each(function()
      local bp
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "kongsumers",
        "jwt_secrets",
      })

      route = bp.routes:insert {
        hosts = { "jwt.com" },
      }

      kongsumer = bp.kongsumers:insert {
        username = "kongsumer1",
      }

      bp.plugins:insert {
        name     = "jwt",
        config   = {},
        route = { id = route.id },
      }

      bp.jwt_secrets:insert {
        key      = "key123",
        secret   = "secret123",
        kongsumer = { id = kongsumer.id },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if admin_client and proxy_client then
        admin_client:close()
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    local PAYLOAD = {
      iss = nil,
      nbf = os.time(),
      iat = os.time(),
      exp = os.time() + 3600
    }

    local function get_authorization(key, secret)
      PAYLOAD.iss = key
      local jwt = jwt_encoder.encode(PAYLOAD, secret)
      return "Bearer " .. jwt
    end

    describe("JWT Credentials entity invalidation", function()
      it("should invalidate when JWT Auth Credential entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(200, res)

        -- Check that cache is populated
        local cache_key = db.jwt_secrets:cache_key("key123")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key,
        })
        assert.res_status(200, res)

        -- Retrieve credential ID
        res = assert(admin_client:send {
          method = "GET",
          path   = "/kongsumers/kongsumer1/jwt/",
        })
        local body = cjson.decode(assert.res_status(200, res))
        local credential_id = body.data[1].id
        assert.truthy(credential_id)

        -- Delete JWT credential (which triggers invalidation)
        res = assert(admin_client:send {
          method = "DELETE",
          path   = "/kongsumers/kongsumer1/jwt/" .. credential_id,
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key
          })
          res:read_body()
          return res.status == 404
        end)

        -- It should not work
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(403, res)
      end)
      it("should invalidate when JWT Auth Credential entity is updated", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(200, res)

        -- It should not work
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("keyhello", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(403, res)

        -- Check that cache is populated
        local cache_key = db.jwt_secrets:cache_key("key123")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key,
        })
        assert.res_status(200, res)

        -- Retrieve credential ID
        res = assert(admin_client:send {
          method = "GET",
          path   = "/kongsumers/kongsumer1/jwt/",
        })
        local body = cjson.decode(assert.res_status(200, res))
        local credential_id = body.data[1].id
        assert.truthy(credential_id)

        -- Patch JWT credential (which triggers invalidation)
        res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/kongsumers/kongsumer1/jwt/" .. credential_id,
          body    = {
            key = "keyhello"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(200, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key
          })
          res:read_body()
          return res.status == 404
        end)

        -- It should work
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("keyhello", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(200, res)

        -- It should not work
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(403, res)
      end)
    end)
    describe("kongsumer entity invalidation", function()
      it("should invalidate when kongsumer entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(200, res)

        -- Check that cache is populated
        local cache_key = db.jwt_secrets:cache_key("key123")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key,
        })
        assert.res_status(200, res)

        -- Delete kongsumer (which triggers invalidation)
        res = assert(admin_client:send {
          method = "DELETE",
          path   = "/kongsumers/kongsumer1",
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(admin_client:send {
            method  = "GET",
            path    = "/cache/" .. cache_key
          })
          res:read_body()
          return res.status == 404
        end)

        -- It should not work
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = get_authorization("key123", "secret123"),
            ["Host"]          = "jwt.com"
          }
        })
        assert.res_status(403, res)
      end)
    end)
  end)
end
