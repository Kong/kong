-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local ldap_groups = require "kong.plugins.ldap-auth-advanced.groups"
local ldap_access = require "kong.plugins.ldap-auth-advanced.access"

local ldap_base_config = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
}

local ldap_base_config2 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "test-group-2" },
}

local ldap_base_config3 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "test-group-3" },
}

local ldap_base_config4 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "testfailedgroup1 test-group-3" },
}

local ldap_base_config5 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "test-group-1 test-group-3" },
}

local ldap_base_config6 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "testfailedgroup1", "testfailedgroup3" },
}

local ldap_base_config7 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "testfailedgroup1", "test-group-3" },
}

local ldap_base_config8 = {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "testfailedgroup1 test-group-3", "testfailedgroup1 testfailedgroup2" },
}

local ldap_base_config9= {
  ldap_host              = "ad-server",
  ldap_password          = "passw2rd1111A$",
  attribute              = "cn",
  base_dn                = "cn=Users,dc=ldap,dc=mashape,dc=com",
  bind_dn                = "cn=Ophelia,cn=Users,dc=ldap,dc=mashape,dc=com",
  consumer_optional      = true,
  hide_credentials       = true,
  cache_ttl              = 2,
  groups_required        = { "test-group-2 test-group-3", "test-group-4", "test-group-1" },
}

describe("validate_groups", function()
  local groups = {
    "CN=test-group-1,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
    "CN=test-group-2,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
    "CN=Test-Group-3,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
  }

  it("should mark groups as valid", function()
    local expected = { "test-group-1", "test-group-2", "Test-Group-3" }

    assert.same(expected, ldap_groups.validate_groups(groups, "CN=Users,DC=addomain,DC=creativehashtags,DC=com", "CN"))
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

  it('returns groups from records with case sensitivity', function()
    assert.same({'Test-Group-3', 'test-group-3'}, ldap_groups.validate_groups({
      groups[3],
      "CN=test-group-3,CN=Users,DC=addomain,DC=creativehashtags,DC=com"
    }, "CN=Users,DC=addomain,DC=creativehashtags,DC=com", "CN"))
  end)

  it("accepts a group with spaces in its name", function()
    local groups = {
      "CN=Test Group 4,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
      "CN= Test Group 5,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
      "CN= Test Group 6 ,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
      "CN=  Test  Group  7  ,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
      "CN= ,CN=Users,DC=addomain,DC=creativehashtags,DC=com", -- group name containing only a space
    }

    local expected = {
      "Test Group 4",
      " Test Group 5",
      " Test Group 6 ",
      "  Test  Group  7  ",
      " ", -- group name containing only a space
    }

    local gbase = "CN=Users,DC=addomain,DC=creativehashtags,DC=com"
    local gattr = "CN"

    assert.same(expected, ldap_groups.validate_groups(groups, gbase, gattr))
  end)
end)

describe("check_group_membership()", function()
  it("conf.groups_required['A'] -> A", function()
    local conf = { groups_required = { "A" } }
    local groups_user = { "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A B'] -> A AND B", function()
    local conf = { groups_required = { "A B" } }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "D" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "D", "C", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A', 'B'] -> A OR B", function()
    local conf = { groups_required = { "A", "B" } }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "C", "D", "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "E", "B", "C" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "G", "E", "D" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A B', 'C D', 'E'] -> (A AND B) OR (C AND D) OR (E)", function()
    local conf = { groups_required = { "A B", "C D", "E" } }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "D" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "A", "B", "C" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "E", "C", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "G", "D", "C", "E" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A', 'B', 'C D'] -> A OR B OR (C AND D)", function()
    local conf = { groups_required = { "A", "B", "C D"} }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C", "D", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "E", "B", "C", "D" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "E", "D", "G", "C" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "Z", "F", "D", "E" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A', 'A'] -> A OR A", function()
    local conf = { groups_required = { "A", "A"} }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "D" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "A", "B", "D" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "E", "D", "C", "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "E", "C", "G" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "F", "Z", "E", "D", "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))
  end)

  it("conf.groups_required['A A'] -> A AND A", function()
    local conf = { groups_required = { "A A"} }
    local groups_user = { "A", "B" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "C", "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "B", "D" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "A", "C", "B", "D" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "E", "D", "C", "B" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "D", "E", "C", "G" }
    assert.falsy(ldap_access.check_group_membership(conf, groups_user))

    groups_user = { "F", "A", "E", "D", "Z" }
    assert.truthy(ldap_access.check_group_membership(conf, groups_user))
  end)
end)

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Plugin: ldap-auth-advanced (groups) [#" .. strategy .. "]", function()
    local proxy_client, admin_client, bp, plugin

    local db_strategy = strategy ~= "off" and strategy or nil

    setup(function()
      bp = helpers.get_db_utils(db_strategy, nil, { "ldap-auth-advanced" })

      local route = bp.routes:insert {
        hosts = { "ldap.com" }
      }

      local route2 = bp.routes:insert {
        hosts = { "ldap2.com" }
      }

      local route3 = bp.routes:insert {
        hosts = { "ldap3.com" }
      }

      local route4 = bp.routes:insert {
        hosts = { "ldap4.com" }
      }

      local route5 = bp.routes:insert {
        hosts = { "ldap5.com" }
      }

      local route6 = bp.routes:insert {
        hosts = { "ldap6.com" }
      }

      local route7 = bp.routes:insert {
        hosts = { "ldap7.com" }
      }

      local route8 = bp.routes:insert {
        hosts = { "ldap8.com" }
      }

      local route9 = bp.routes:insert {
        hosts = { "ldap9.com" }
      }

      plugin = bp.plugins:insert {
        route = { id = route.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config2,
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config3,
      }

      bp.plugins:insert {
        route = { id = route4.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config4,
      }

      bp.plugins:insert {
        route = { id = route5.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config5,
      }

      bp.plugins:insert {
        route = { id = route6.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config6,
      }

      bp.plugins:insert {
        route = { id = route7.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config7,
      }

      bp.plugins:insert {
        route = { id = route8.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config8,
      }

      bp.plugins:insert {
        route = { id = route9.id },
        name     = "ldap-auth-advanced",
        config   = ldap_base_config9,
      }
    end)

    before_each(function()
      assert(helpers.start_kong({
        plugins = "ldap-auth-advanced",
        database   = db_strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

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

      helpers.stop_kong()
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
            config = { ldap_port = 636, ldaps = true }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(636, json.config.ldap_port)
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
        assert.are.equal("test-group-2, test-group-3", value)

        -- resetting plugin to LDAP
        local res = assert(admin_client:send {
          method  = "PATCH",
          path    = "/plugins/" .. plugin.id,
          body    = {
            config = { ldap_port = 389, ldaps = false }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(389, json.config.ldap_port)
        assert.equal(false, json.config.ldaps)
      end)

      it("should deny request based on user's group membership", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap2.com",
            authorization    = "ldap " .. ngx.encode_base64("Hamlet:passw2rd1111A$"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal(json.message, "User not in authorized LDAP Group")
      end)

      it("should allow request based on user's group membership", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap3.com",
            authorization    = "ldap " .. ngx.encode_base64("Othello:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.equal("test-group-3", value)
      end)

      it("should deny request when user is not member of any group", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap3.com",
            authorization    = "ldap " .. ngx.encode_base64("Kipp:passw2rd1111A$"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal(json.message, "User not in authorized LDAP Group")
      end)

      it("validate multiple groups with AND (negative test)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap4.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal(json.message, "User not in authorized LDAP Group")
      end)

      it("validate multiple groups with AND", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap5.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.equal("test-group-1, test-group-3", value)
      end)

      it("validate multiple groups with OR (negative test)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap6.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal(json.message, "User not in authorized LDAP Group")
      end)

      it("validate multiple groups with OR", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap7.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.equal("test-group-1, test-group-3", value)
      end)

      it("validate multiple groups with complex OR/AND combination (negative test)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap8.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.equal(json.message, "User not in authorized LDAP Group")
      end)

      it("validate multiple groups with complex OR/AND combination", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          body    = {},
          headers = {
            host             = "ldap9.com",
            authorization    = "ldap " .. ngx.encode_base64("MacBeth:passw2rd1111A$"),
          }
        })

        assert.res_status(200, res)
        local value = assert.request(res).has.header("x-authenticated-groups")
        assert.equal("test-group-1, test-group-3", value)
      end)
    end)
  end)
end
