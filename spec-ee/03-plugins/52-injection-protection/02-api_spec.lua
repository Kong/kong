-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"



for _, strategy in helpers.each_strategy() do
  describe("Plugin: injection-protection (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("with default config", function()
      local route

      lazy_setup(function()
        local service = bp.services:insert()

        route = bp.routes:insert {
          hosts      = { "test1.test" },
          protocols  = { "http", "https" },
          service    = service,
        }

        assert(helpers.start_kong({
          database   = strategy,
          log_level  = "warn",
          plugins    = "bundled,injection-protection",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      after_each(function()
        admin_client:delete("/routes/" .. route.id ..  "/plugins/injection-protection-test")
      end)

      lazy_teardown(function()

        if admin_client then
          admin_client:close()
        end

        helpers.stop_kong()
      end)

      it("should create plugin instance successfully", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "injection-protection",
            instance_name = "injection-protection-test",
            route = { id = route.id },
            config = {
              injection_types = {
                "sql",
              },
              enforcement_mode = "log_only",
              error_status_code = 400,
              error_message = "Bad Request",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })

        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("injection-protection-test", body.instance_name)

      end)

      it("should save with proper config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "injection-protection",
            instance_name = "injection-protection-test",
            route = { id = route.id },
            config = {
              injection_types = {
                "sql",
              },
              locations = {
                "headers",
                "path_and_query",
                "body",
              },
              enforcement_mode = "log_only",
              error_status_code = 400,
              error_message = "Bad Request",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("sql", body.config.injection_types[1])
        assert.equal("headers", body.config.locations[1])
        assert.equal("path_and_query", body.config.locations[2])
        assert.equal("body", body.config.locations[3])
        assert.equal(400, body.config.error_status_code)
        assert.equal("Bad Request", body.config.error_message)
        assert.equal("injection-protection-test", body.instance_name)
        assert.equal("injection-protection", body.name)
        assert.equal("log_only", body.config.enforcement_mode)

      end)

    end)
    

  end)
end

