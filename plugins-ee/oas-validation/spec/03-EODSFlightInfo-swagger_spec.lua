-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local cjson     = require("cjson.safe").new()

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name petstore.test;
          listen 12345;

          location ~ "/test" {
            content_by_lua_block {
              local body = "[{ \"foo\": \"bar\" }]"
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.header["Content-Length"] = #body
              ngx.print(body)
            }
          }
        }
    ]]
  }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

      lazy_setup(function()
        local bp, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        }, { PLUGIN_NAME })

        local service1 = bp.services:insert{
          protocol = "http",
          port     = 12345,
          host     = "127.0.0.1",
          path     = "/test"
        }

        local route1 = db.routes:insert({
          hosts = { "eods.test" },
          paths = { "/" },
          service    = service1,
        }
      )

      -- add the plugin to test to the route we created
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        service = { id = service1.id },
        route = { id = route1.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/ICC-EODSFlightInformation-1.5.5-swagger.yaml"):read("*a")),
          verbose_response = true
        },
      })

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("EODSFlightInfo tests", function()
      it("/flightScheduleList/timeRange - happy path", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightScheduleList/timeRange",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            schDTS = "2015-01-20T06:00:00Z",
            schDTE = "2015-01-20T06:00:00Z",
            depArrInd = "A",
            airportCode = "ABC",
            incCarrierList = "CA",
            excCarrierList = "CA",
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(res).has.status(200)

      end)

      it("/flightScheduleList/timeRange - missing required header X-applicationName", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightScheduleList/timeRange",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            schDTS = "2015-01-20T06:00:00Z",
            schDTE = "2015-01-20T06:00:00Z",
            depArrInd = "A",
            airportCode = "ABC",
            incCarrierList = "CA",
            excCarrierList = "CA",
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("header 'X-applicationName' validation failed with error: 'required parameter value not found in request'", json.message)
      end)

      it("/flightScheduleList/timeRange - required header X-applicationName does not match pattern", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightScheduleList/timeRange",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CX",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            schDTS = "2015-01-20T06:00:00Z",
            schDTE = "2015-01-20T06:00:00Z",
            depArrInd = "A",
            airportCode = "ABC",
            incCarrierList = "CA",
            excCarrierList = "CA",
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("header 'X-applicationName' validation failed with error: 'failed to match pattern [a-zA-Z]{4,10} with \"CX\"'", json.message)
      end)

      it("/flightScheduleList/timeRange - missing required query depArrInd", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightScheduleList/timeRange",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            schDTS = "2015-01-20T06:00:00Z",
            schDTE = "2015-01-20T06:00:00Z",
            airportCode = "ABC",
            incCarrierList = "CA",
            excCarrierList = "CA",
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("query 'depArrInd' validation failed with error: 'required parameter value not found in request'", json.message)
      end)

      it("/flightScheduleList/timeRange - required query depArrInd does not match enum", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightScheduleList/timeRange",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            schDTS = "2015-01-20T06:00:00Z",
            schDTE = "2015-01-20T06:00:00Z",
            depArrInd = "X",
            airportCode = "ABC",
            incCarrierList = "CA",
            excCarrierList = "CA",
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("query 'depArrInd' validation failed with error: 'matches none of the enum values'", json.message)
      end)

      it("/flightStatus/pts - no body", function()
        local res = assert(client:send {
          method = "POST",
          path = "/flightStatus/pts",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          body = {
            {
            }
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("body 'sectors' validation failed with error: 'wrong type: expected object, got array'", json.message)
      end)

      it("/flightStatus/pts - happy path", function()
        local res = assert(client:send {
          method = "POST",
          path = "/flightStatus/pts",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          body = {
            sectors = { {
                arrivalPort = "NRT",
                carrier = "CX",
                departurePort = "HKG",
                flightNumber = "500",
                stdFlightDate = "2018-12-11"
              } }
          }
        })
        assert.response(res).has.status(200)
      end)

      it("/flightStatus/pts - missing required body carrier", function()
        local res = assert(client:send {
          method = "POST",
          path = "/flightStatus/pts",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          body = {
            sectors = { {
                arrivalPort = "NRT",
                departurePort = "HKG",
                flightNumber = "500",
                stdFlightDate = "2018-12-11"
              } }
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("body 'sectors' validation failed with error: 'property sectors validation failed: failed to validate item 1: property carrier is required'", json.message)
      end)

      it("/flightStatus/pts - invalid date format in body", function()
        local res = assert(client:send {
          method = "POST",
          path = "/flightStatus/pts",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          body = {
            sectors = { {
                arrivalPort = "NRT",
                carrier = "CX",
                departurePort = "HKG",
                flightNumber = "500",
                stdFlightDate = "notadate"
              } }
          }
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("body 'sectors' validation failed with error: 'property sectors validation failed: failed to validate item 1: property stdFlightDate validation failed: expected valid \"date\", got \"notadate\"'", json.message)
      end)

      it("/flightStatus/{flightNumber}/origin/{origin} - happy path", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightStatus/123/origin/HKG",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            stdLocalDate = "2018-12-10",
            stdUTCDate = "2018-12-10",
          }
        })
        assert.response(res).has.status(200)
      end)

      it("/flightStatus/{flightNumber}/origin/ - missing uri parameter", function()
        local res = assert(client:send {
          method = "GET",
          path = "/flightStatus/123/origin/123",
          headers = {
            host = "eods.test",
            ["Content-Type"] = "application/json",
            ["X-applicationName"] = "CXMOBILE",
            ["X-correlationId"] = "550e8400-e29b-41d4-a716-446655440000",
            ["Authorization"] = "Basic dXNlcm5hbWU6cGFzc3dvcmQ=",
          },
          query = {
            stdLocalDate = "2018-12-10",
            stdUTCDate = "2018-12-10",
          }
        })
        assert.response(res).has.status(200)
      end)

    end)

  end)
end
