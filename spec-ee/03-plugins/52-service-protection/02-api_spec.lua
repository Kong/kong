-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"
local cjson = require "cjson"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


for _, strategy in helpers.each_strategy() do
  describe("Plugin: service-protection (API) [#" .. strategy .. "]", function()
    local admin_client
    local bp

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
      })

      assert(helpers.start_kong({
        database   = strategy,
        portal_and_vitals_key = get_portal_and_vitals_key()
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("POST", function()

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("transparently sorts limit/window_size pairs", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/plugins",
          body = {
            name = "service-protection",
            config = {
              strategy = "cluster",
              window_size = { 3600, 60 },
              limit = { 100, 10 },
              sync_rate = 10,
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
  
        table.sort(json.config.limit)
        table.sort(json.config.window_size)
  
        assert.same({ 10, 100 }, json.config.limit)
        assert.same({ 60, 3600 }, json.config.window_size)
      end)

      it("cannot be applied to a route", function()
        local route = bp.routes:insert {
          hosts = { "test1.test" },
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "service-protection",
            route = { id = route.id },
            config = {
              strategy = "cluster",
              window_size = { 3600, 60 },
              limit = { 100, 10 },
              sync_rate = 10,
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          fields = {
            route = 'value must be null',
          },
          message = "schema violation (route: value must be null)",
        }, json)
      end)

      it("cannot be applied to a consumer", function()
        local consumer = bp.consumers:insert {
          username = "proxybob",
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "service-protection",
            consumer = { id = consumer.id },
            config = {
              strategy = "cluster",
              window_size = { 3600, 60 },
              limit = { 100, 10 },
              sync_rate = 10,
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          name = "schema violation",
          fields = {
            consumer = 'value must be null',
          },
          message = "schema violation (consumer: value must be null)",
        }, json)
      end)

      it("can be applied to a service", function()
        local service = bp.services:insert {
          host = "test1.test",
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "service-protection",
            service = { id = service.id },
            config = {
              strategy = "cluster",
              window_size = { 3600, 60 },
              limit = { 100, 10 },
              sync_rate = 10,
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)
      end)
    end)
  end)
end

