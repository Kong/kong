local helpers = require "spec.helpers"
local fmt = string.format
local lower = string.lower
local md5 = ngx.md5

local ldap_host_aws = "ec2-54-172-82-117.compute-1.amazonaws.com"

local ldap_strategies = {
  non_secure = { name = "non-secure", start_tls = false },
  start_tls = { name = "starttls", start_tls = true }
}

for _, ldap_strategy in pairs(ldap_strategies) do
  describe("Connection strategy [" .. ldap_strategy.name .. "]", function()
    for _, strategy in helpers.each_strategy() do
      describe("Plugin: ldap-auth (invalidation) [#" .. strategy .. "]", function()
        local admin_client
        local proxy_client
        local plugin

        lazy_setup(function()
          local bp = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
          })

          local route = bp.routes:insert {
            hosts = { "ldapauth.com" },
          }

          plugin = bp.plugins:insert {
            route = { id = route.id },
            name     = "ldap-auth",
            config   = {
              ldap_host = ldap_host_aws,
              ldap_port = 389,
              start_tls = ldap_strategy.start_tls,
              base_dn   = "ou=scientists,dc=ldap,dc=mashape,dc=com",
              attribute = "uid",
              cache_ttl = 1,
            }
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))
        end)

        before_each(function()
          admin_client = helpers.admin_client()
          proxy_client = helpers.proxy_client()
        end)

        after_each(function()
          if admin_client then
            admin_client:close()
          end
          if proxy_client then
            proxy_client:close()
          end
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true)
        end)

        local function cache_key(conf, username, password)
            local ldap_config_cache = md5(fmt("%s:%u:%s:%s:%u",
              lower(conf.ldap_host),
              conf.ldap_port,
              conf.base_dn,
              conf.attribute,
              conf.cache_ttl
            ))

          return fmt("ldap_auth_cache:%s:%s:%s", ldap_config_cache,
                     username, password)
        end

        describe("authenticated LDAP user get cached", function()
          it("should cache invalid credential", function()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/requests",
              body = {},
              headers = {
                ["HOST"] = "ldapauth.com",
                authorization = "ldap " .. ngx.encode_base64("einstein:wrongpassword")
              }
            })
            assert.res_status(401, res)

            local cache_key = cache_key(plugin.config, "einstein", "wrongpassword")
            res = assert(admin_client:send {
              method = "GET",
              path   = "/cache/" .. cache_key,
              body   = {},
            })
            assert.res_status(200, res)
          end)
          it("should invalidate negative cache once ttl expires", function()
            local cache_key = cache_key(plugin.config, "einstein", "wrongpassword")

            helpers.wait_for_invalidation(cache_key)
          end)
          it("should cache valid credential", function()
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
            local cache_key = cache_key(plugin.config, "einstein", "password")
            res = assert(admin_client:send {
              method = "GET",
              path   = "/cache/" .. cache_key,
              body   = {},
            })
            assert.res_status(200, res)
          end)
          it("should invalidate cache once ttl expires", function()
            local cache_key = cache_key(plugin.config, "einstein", "password")

            helpers.wait_for_invalidation(cache_key)
          end)
        end)
      end)
    end
  end)
end
