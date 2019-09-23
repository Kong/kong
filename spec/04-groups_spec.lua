local helpers = require "spec.helpers"
local cjson = require "cjson"
local ldap_groups = require "kong.plugins.ldap-auth-advanced.groups"

local ldap_base_config = {
  ldap_host              = "localhost",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
}

describe("validate_groups", function()
  local groups = {
    "CN=test-group-1,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
    "CN=test-group-2,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
  }
  
  it("should mark groups as valid", function()
    local expected = { "test-group-1", "test-group-2" }

    assert.same(expected, ldap_groups.validate_groups(groups, "CN=Users,DC=addomain,DC=creativehashtags,DC=com", "CN"))
    assert.same(expected, ldap_groups.validate_groups(groups, "CN=Users,DC=addomain,DC=creativehashtags,DC=com", "cn"))
    assert.same(expected, ldap_groups.validate_groups(groups, "cn=Users,DC=addomain,dc=creativehashtags,DC=com", "CN"))
    
    -- returns table even when passed as string
    assert.same({expected[1]}, ldap_groups.validate_groups(groups[1], "CN=Users,DC=addomain,DC=creativehashtags,DC=com", "CN"))
  end)
  
  it("should mark groups as invalid", function()
    assert.same(nil, ldap_groups.validate_groups(groups, "cn=Users,DC=addomain,dc=creativehashtags,DC=com", "dc"))
    assert.same(nil, ldap_groups.validate_groups(groups, "dc=creativehashtags,DC=com", "CN"))
    assert.same(nil, ldap_groups.validate_groups(groups, "CN=addomain,CN=creativehashtags,CN=com", "CN"))
  end)
  
  it("filters out invalid groups and returns valid groups", function()
    assert.same({"test-group-1"}, ldap_groups.validate_groups({
      groups[1],
      "CN=invalid-group-dn,CN=Users,CN=addomain,CN=creativehashtags,CN=com"
    }, "cn=Users,DC=addomain,dc=creativehashtags,DC=com", "CN"))
  end)
end)

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
      it("should set groups from search result with a single group", function()
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
      
      it("should set groups from search result with more than one group", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.are.equal("test-group-1, test-group-3", value)
      end)
      
      it("should set groups from search result with explicit group_base_dn", function()
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

      it("should operate over LDAPS", function()
        local res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { port = 636, ldaps = true }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(636, json.config.port)
        assert.equal(true, json.config.ldaps)

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap.com",
            authorization    = "ldap " .. ngx.encode_base64("Desdemona:passw2rd1111A$"),
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.are.equal("test-group-2", value)

        -- resetting plugin to LDAP
        local res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { port = 389, ldaps = false }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(389, json.config.port)
        assert.equal(false, json.config.ldaps)
      end)
    end)
  end)
end
