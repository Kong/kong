-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Use-case description:
-- As an API Owner, I want to allow GET/POST/PUT access all consumers with role dev.
-- In addition I want only DELETE to be available to consumers with role API Admin

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

      local a_cg = "developer_group"
      local b_cg = "admin_group"

      local developer_and_admin = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local admin_only = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local developer_only = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local developer_group = assert(db.consumer_groups:insert { name = a_cg })
      local admin_group = assert(db.consumer_groups:insert { name = b_cg })

      -- Add consumers to consumer groups
      -- consumer is in both groups
      local a_mapping = {
        consumer       = { id = developer_and_admin.id },
        consumer_group = { id = developer_group.id },
      }
      local ab_mapping = {
        consumer       = { id = developer_and_admin.id },
        consumer_group = { id = admin_group.id },
      }
      -- consumer is only in admin_group
      local b_mapping = {
        consumer       = { id = admin_only.id },
        consumer_group = { id = admin_group.id },
      }
      -- consumer is only in developer_group
      local c_mapping = {
        consumer       = { id = developer_only.id },
        consumer_group = { id = developer_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))
      assert(db.consumer_group_consumers:insert(ab_mapping))
      assert(db.consumer_group_consumers:insert(b_mapping))
      assert(db.consumer_group_consumers:insert(c_mapping))

      -- Assign keys to all consumers
      assert(bp.keyauth_credentials:insert {
        key = "developer_and_admin",
        consumer = { id = developer_and_admin.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "admin_only",
        consumer = { id = admin_only.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "developer_only",
        consumer = { id = developer_only.id },
      })

      -- create a route that matches all methods except DELETE
      -- and host acl2.test
      local route_matching_non_delete = bp.routes:insert {
        expression = [[http.host == "acl2.test" && http.method != "DELETE"]],
      }

      -- create a route that matches DELETE
      -- and host acl2.test
      local route_matching_delete = bp.routes:insert {
        expression = [[net.protocol == "http" && http.host == "acl2.test" && http.method == "DELETE"]],
      }

      -- Setup a ACL plugin for the route that matches all methods except DELETE
      -- and only allow the developer_group (and admins)
      bp.plugins:insert {
        name = "acl",
        route = { id = route_matching_non_delete.id },
        config = {
          allow = { "developer_group", "admin_group" },
          include_consumer_groups = true,
        }
      }

      -- Setup a ACL plugin for the route that matches DELETE
      -- and only allow the admin_group
      bp.plugins:insert {
        name = "acl",
        route = { id = route_matching_delete.id },
        config = {
          allow = { "admin_group" },
          include_consumer_groups = true,
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        config = {}
      }

      assert(helpers.start_kong({
        plugins                  = "bundled, ctx-checker",
        database                 = strategy,
        router_flavor            = "expressions",
        nginx_conf               = "spec/fixtures/custom_nginx.template",
        db_cache_warmup_entities = "keyauth_credentials,consumers,acls,consumer-groups",
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

    it("ALLOW GET/PATCH/PUT/POST for admins and developers", function()
      for _, apikey in ipairs({ "developer_only", "developer_and_admin" }) do
        for _, method in ipairs({ "GET", "PATCH", "POST", "PUT" }) do
          local res = assert(proxy_client:send {
            method = method,
            path = "/request",
            headers = {
              ["ApiKey"] = apikey,
              ["Host"] = "acl2.test"
            }
          })
          assert.res_status(200, res)
        end
      end
    end)

    it("ALLOW DELETE for admins only", function()
      for _, apikey in ipairs({ "admin_only", "developer_and_admin" }) do
        local res = assert(proxy_client:send {
          method = "DELETE",
          path = "/request",
          headers = {
            ["ApiKey"] = apikey,
            ["Host"] = "acl2.test"
          }
        })
        assert.res_status(200, res)
      end
    end)

    it("DENY DELETE for developers", function()
      for _, apikey in ipairs({ "developer_only" }) do
        local res = assert(proxy_client:send {
          method = "DELETE",
          path = "/request",
          headers = {
            ["ApiKey"] = apikey,
            ["Host"] = "acl2.test"
          }
        })
        assert.res_status(403, res)
      end
    end)
  end)
end
