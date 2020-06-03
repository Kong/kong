local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: application-registration (API) [#" .. strategy .. "]", function()
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

      it("cannot be applied to a route", function()
        local route = bp.routes:insert {
          hosts = { "test1.test" },
        }
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "application-registration",
            route = { id = route.id },
            config = {
              display_name = "my service",
            },
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
            service = 'value must not be null',
          },
          message = "2 schema violations (route: value must be null; service: value must not be null)",
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
            name  = "application-registration",
            consumer = { id = consumer.id },
            config = {
              display_name = "my service",
            },
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
            service = 'value must not be null',
          },
          message = "2 schema violations (consumer: value must be null; service: value must not be null)",
        }, json)
      end)

      it("cannot be applied globally", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "application-registration",
            config = {
              display_name = "my service",
            },
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
            service = 'value must not be null'
          },
          message = "schema violation (service: value must not be null)",
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
            name  = "application-registration",
            service = { id = service.id },
            config = {
              display_name = "my service",
            },
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
