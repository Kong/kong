-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          server_name petstore1.test;
          listen 12345;

          location ~ "/users" {
            return 200;
          }

        }
    ]]
  }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, { PLUGIN_NAME, "sleeper" })

      local service = assert(bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      })
      local route = assert(db.routes:insert({
        hosts = { "petstore1.test" },
        service = service,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/thread-safe.yaml"):read("*a")),
          validate_response_body = true,
          validate_request_header_params = false,
          validate_request_query_params = true,
          validate_request_uri_params = true,
          header_parameter_check = false,
          query_parameter_check = true,
          verbose_response = true
        },
      })
      assert(bp.plugins:insert {
        name = "sleeper",
        route = { id = route.id },
        config = {},
      })


      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,sleeper," .. PLUGIN_NAME,
        lua_package_path  = "?./spec-ee/fixtures/custom_plugins/?.lua",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    it("thread safe", function()
      local r1 = {
        method = "POST",
        path = "/users",
        headers = {
          host = "petstore1.test",
          ["Content-Type"] = "application/json",
          ["NGX-Req-Get-Body-Data-Sleep"] = 2,
        },
        query = {
        },
        body = {
          userName = "test"
        }
      }
      local r1_result = {}
      local r2 = {
        method = "POST",
        path = "/users",
        headers = {
          host = "petstore1.test",
          ["Content-Type"] = "application/json",
          ["NGX-Req-Get-Body-Data-Sleep"] = 1,
        },
        query = {
          type = true,
        },
        body = {
          userName = "test"
        }
      }
      local r2_result = {}


      local send_request = function(request, result)
        return function()
          local tmp_client = helpers.proxy_client()
          local res = assert(tmp_client:send(request))
          result.status = res.status
        end
      end

      local thread_1 = ngx.thread.spawn(send_request(r1, r1_result))
      local thread_2 = ngx.thread.spawn(send_request(r2, r2_result))
      ngx.thread.wait(thread_1)
      ngx.thread.wait(thread_2)

      assert.equals(400, r1_result.status)
      assert.equals(200, r2_result.status)
    end)

  end)
end
