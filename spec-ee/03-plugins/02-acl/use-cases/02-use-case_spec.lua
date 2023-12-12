-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Use-case description:
-- As an API Owner/team I want to allow GET access to all routes for internal consumers
-- as well as those from a partner.
-- internal users have role internal
-- partners will login with email ending in *.apipartner.io


local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"

local function reload_router(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  helpers.setenv("KONG_ROUTER_FLAVOR", flavor)

  package.loaded["spec.helpers"] = nil
  package.loaded["kong.global"] = nil
  package.loaded["kong.cache"] = nil
  package.loaded["kong.db"] = nil
  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  helpers = require "spec.helpers"

  helpers.unsetenv("KONG_ROUTER_FLAVOR")
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: ACL (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local bp
    local db

    reload_router("expressions")

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "consumer-groups",
        "acls",
        "keyauth_credentials",
      }, { "ctx-checker" })

      local a_cg = "internal_group"
      local b_cg = "external_group"

      local internal_user = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local external_user = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      local internal_group = assert(db.consumer_groups:insert { name = a_cg })
      local external_group = assert(db.consumer_groups:insert { name = b_cg })

      -- internal consumer is in `internal` group
      local a_mapping = {
        consumer       = { id = internal_user.id },
        consumer_group = { id = internal_group.id },
      }
      -- external_user is not part of external_group
      local b_mapping = {
        consumer       = { id = external_user.id },
        consumer_group = { id = external_group.id },
      }

      assert(db.consumer_group_consumers:insert(a_mapping))
      assert(db.consumer_group_consumers:insert(b_mapping))

      -- Assign keys to all consumers
      assert(bp.keyauth_credentials:insert {
        key = "external",
        consumer = { id = external_user.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "internal",
        consumer = { id = internal_user.id },
      })

      -- create a route that matches GET and host acl2.test
      local route = bp.routes:insert {
        expression = [[http.path == "/internal" && http.method == "GET" ]],
      }

      -- create a route that matches GET and host acl2.test
      local route2 = bp.routes:insert {
        expression = [[http.path == "/internal-x" && http.method == "GET" ]],
      }

      -- Setup a ACL plugin for the route that matches a certain host
      bp.plugins:insert {
        name = "acl",
        route = { id = route.id },
        config = {
          allow = { "internal_group" },
          include_consumer_groups = true,
        }
      }

      -- Setup a ACL plugin for the route that matches a certain host
      bp.plugins:insert {
        name = "acl",
        route = { id = route2.id },
        config = {
          allow = { "internal_group" },
          include_consumer_groups = true,
        }
      }

      -- Pretend that the ctx.shared.authenticated_groups is set
      -- via a authentication plugin
      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route2.id },
        config = {
          ctx_kind      = "kong.ctx.shared",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "internal_group" },
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route.id },
        config = {}
      }

      assert(helpers.start_kong({
        plugins                  = "bundled, ctx-checker",
        database                 = strategy,
        router_flavor            = "expressions",
        nginx_conf               = "spec/fixtures/custom_nginx.template",
        db_cache_warmup_entities = "keyauth_credentials,consumers,acls,consumer_groups",
      }))
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      proxy_client:close()
      admin_client:close()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("ALLOW GET for internals", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/internal",
        headers = {
          ["ApiKey"] = "internal",
        }
      })
      assert.res_status(200, res)
    end)

    it("DENY GET for externals", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/internal",
        headers = {
          ["ApiKey"] = "external",
        }
      })
      assert.res_status(403, res)
    end)

    it("ALLOW GET for internals (authenticated via tokens/claims/ldap)", function()
      local res = assert(proxy_client:send {
        method = "GET",
        -- ctx-setter sets the `internal_group` here.
        path = "/internal-x",
      })
      assert.res_status(200, res)
    end)
  end)
end
