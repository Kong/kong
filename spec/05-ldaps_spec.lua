local helpers = require "spec.helpers"
local cjson = require "cjson"

local ldap_base_config = {
  ldap_host              = "localhost",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  ldap_port              = 636,
  start_tls              = false,
  ldaps                  = true,
}

for _, strategy in helpers.each_strategy() do
  describe("Plugin: ldap-auth-advanced (groups) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, bp, plugin

    setup(function()
      bp = helpers.get_db_utils(strategy, nil, { "ldap-auth-advanced" })

      local route = bp.routes:insert {
        hosts = { "ldap.com" }
      }

      plugin = bp.plugins:insert {
        route = { id = route.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config
      }

      assert(helpers.start_kong({
        plugins = "ldap-auth-advanced",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end

      if admin_client then
        admin_client:close()
      end
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("authenticated groups", function()

      it("should function over ldaps", function()
        local res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { group_base_dn = "CN=Users,dc=ldap,dc=mashape,dc=com" }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("CN=Users,dc=ldap,dc=mashape,dc=com", json.config.group_base_dn)

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap.com",
            authorization    = "ldap " .. ngx.encode_base64("User1:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.are.equal("test-group-1", value)
      end)
    end)
  end)
end
