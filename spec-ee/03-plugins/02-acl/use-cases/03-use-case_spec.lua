-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Use-case description:
-- As an service team developing new service, I want version 2 to be
-- available to only users who have signed up to be beta testers
-- Consumer-group called betatesters is created and consumers added to
-- that group

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

      local a_cg = "alpha_testers"
      local b_cg = "beta_testers"
      local c_cg = "normal_users"

      local beta_tester = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local alpha_tester = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local normal_user = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      local alpha_testers = assert(db.consumer_groups:insert { name = a_cg })
      local beta_testers = assert(db.consumer_groups:insert { name = b_cg })
      local normal_users = assert(db.consumer_groups:insert { name = c_cg })

      local a_mapping = {
        consumer       = { id = beta_tester.id },
        consumer_group = { id = beta_testers.id },
      }
      local b_mapping = {
        consumer       = { id = alpha_tester.id },
        consumer_group = { id = alpha_testers.id },
      }
      local c_mapping = {
        consumer       = { id = normal_user.id },
        consumer_group = { id = normal_users.id },
      }

      assert(db.consumer_group_consumers:insert(a_mapping))
      assert(db.consumer_group_consumers:insert(b_mapping))
      assert(db.consumer_group_consumers:insert(c_mapping))

      -- Assign keys to all consumers
      assert(bp.keyauth_credentials:insert {
        key = "alpha_tester",
        consumer = { id = alpha_tester.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "beta_tester",
        consumer = { id = beta_tester.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "normal_user",
        consumer = { id = normal_user.id },
      })

      local beta_service = bp.services:insert {
        name = "beta-service",
        path = "/status/200"
      }

      local normal_service = bp.services:insert {
        name = "normal-service",
        path = "/status/200",
      }

      local alpha_service = bp.services:insert {
        name = "alpha-service",
        path = "/status/200"
      }

      local beta_route = bp.routes:insert {
        expression = [[ http.queries.beta == "true" ]],
        service = { id = beta_service.id },
      }

      local alpha_route = bp.routes:insert {
        expression = [[ http.queries.alpha == "true" ]],
        service = { id = alpha_service.id },
      }

      local normal_route = bp.routes:insert {
        expression = [[ (http.queries.alpha != "true" && http.queries.beta != "true") ]],
        service = { id = normal_service.id },
      }


      bp.plugins:insert {
        name = "acl",
        route = { id = alpha_route.id },
        config = {
          allow = { "alpha_testers" },
          include_consumer_groups = true,
        }
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = beta_route.id },
        config = {
          allow = { "beta_testers" },
          include_consumer_groups = true,
        }
      }

      bp.plugins:insert {
        name = "acl",
        route = { id = normal_route.id },
        config = {
          allow = { "normal_users", "beta_testers", "alpha_testers" },
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

    it("ALLOW betatesters to the beta-service (via route)", function()
      local res = assert(proxy_client:send {
        path = "/?beta=true",
        headers = {
          ["ApiKey"] = "beta_tester",
        }
      })
      assert.res_status(200, res)
    end)

    it("DENY alphatesters to the beta-service (via route)", function()
      for _, apikey in ipairs({ "alpha_tester", "normal_user" }) do
        local res = assert(proxy_client:send {
          path = "/?beta=true",
          headers = {
            ["ApiKey"] = apikey
          }
        })
        assert.res_status(403, res)
      end
    end)

    it("ALLOW alphatesters to the alpha-service (via route)", function()
      local res = assert(proxy_client:send {
        path = "/?alpha=true",
        headers = {
          ["ApiKey"] = "alpha_tester",
        }
      })
      assert.res_status(200, res)
    end)

    it("DENY betatesters and the normal_user to the alpha-service (via route)", function()
      for _, apikey in ipairs({ "beta_tester", "normal_user" }) do
        local res = assert(proxy_client:send {
          path = "/?alpha=true",
          headers = {
            ["ApiKey"] = apikey
          }
        })
        assert.res_status(403, res)
      end
    end)

    it("ALLOW alphatesters and betatesters and the normal_user to the to the normal-service (via route)", function()
      for _, apikey in ipairs({ "alpha_tester", "beta_tester", "normal_user" }) do
        local res = assert(proxy_client:send {
          path = "/?beta=false&alpha=false",
          headers = {
            ["ApiKey"] = apikey,
          }
        })
        assert.res_status(200, res)
      end
    end)
  end)
end
