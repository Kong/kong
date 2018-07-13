local helpers = require "spec.helpers"
local cjson = require "cjson"
local fmt = string.format
local lower = string.lower
local md5 = ngx.md5

local ldap_host_aws = "ec2-54-172-82-117.compute-1.amazonaws.com"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: ldap-auth (invalidations) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local plugin

    setup(function()
      local bp
      bp = helpers.get_db_utils(strategy)

      local route = bp.routes:insert {
        hosts = { "ldapauth.com" },
      }

      plugin = bp.plugins:insert {
        route_id = route.id,
        name     = "ldap-auth",
        config   = {
          ldap_host = ldap_host_aws,
          ldap_port = "389",
          start_tls = false,
          base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
          attribute = "uid"
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    local function cache_key(conf, username)
        local ldap_config_cache = md5(fmt("%s:%u:%s:%s:%u",
          lower(conf.ldap_host),
          conf.ldap_port,
          conf.base_dn,
          conf.attribute,
          conf.cache_ttl
        ))

      return fmt("ldap_auth_cache:%s:%s", ldap_config_cache, username)
    end

    describe("authenticated LDAP user get cached", function()
      it("should invalidate when Hmac Auth Credential entity is deleted", function()
        -- It should work
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          body = {},
          headers = {
            ["HOST"] = "ldapauth.com",
            authorization = "ldap " .. ngx.encode_base64("einstein:password")
          }
        })
        assert.res_status(200, res)

        -- Check that cache is populated
        local cache_key = cache_key(plugin.config, "einstein")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key,
          body   = {},
        })
        assert.res_status(200, res)
      end)
      it("should not do negative cache", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          body = {},
          headers = {
            ["HOST"] = "ldapauth.com",
            authorization = "ldap " .. ngx.encode_base64("einstein:wrongpassword")
          }
        })
        assert.res_status(403, res)

        local cache_key = cache_key(plugin.config, "einstein")
        res = assert(admin_client:send {
          method = "GET",
          path   = "/cache/" .. cache_key,
          body   = {},
        })
        local body = assert.res_status(200, res)
        assert.is_equal("password", cjson.decode(body).password)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          body = {},
          headers = {
            ["HOST"] = "ldapauth.com",
            authorization = "ldap " .. ngx.encode_base64("einstein:password")
          }
        })
        assert.res_status(200, res)
      end)
    end)
  end)
end
