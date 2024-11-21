-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"

local PLUGIN_NAME = "oas-validation"

local fixtures = {
  http_mock = {
    validation_plugin = [[
      server {
          listen 12345;

          location = "/notify" {
            return 200;
          }

          location = "/notify-with-body" {
            content_by_lua_block {
              ngx.status = 200
              ngx.header["Content-Type"] = "application/json"
              ngx.print('{"key": "string"}')
            }
          }

          location = "/multiple-content-types" {
            content_by_lua_block {
              ngx.status = 200
              ngx.header["Content-Type"] = "text/plain"
              ngx.print("world")
            }
          }

          location = "/content_type_with_charset" {
            return 200;
          }
          
          location = "/content_type_without_charset" {
            return 200;
          }

        }
    ]]
  }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client, admin
    local plugin2

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, { PLUGIN_NAME })

      local service1 = assert(bp.services:insert {
        protocol = "http",
        port = 12345,
        host = "127.0.0.1",
      })

      local route1 = assert(db.routes:insert({
        hosts = { "test1.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/request-body-oas.yaml"):read("*a")),
          validate_request_body = true,
          verbose_response = true,
        },
      })

      local route2 = assert(db.routes:insert({
        hosts = { "test2.test" },
        service = service1,
      }))
      plugin2 = assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/request-body-oas.yaml"):read("*a")),
          validate_request_body = true,
          validate_response_body = true,
          notify_only_request_validation_failure = true,
        },
      })

      local route3 = assert(db.routes:insert({
        hosts = { "test3.test" },
        service = service1,
      }))
      assert(db.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = {
          api_spec = assert(io.open(helpers.get_fixtures_path() .. "/resources/request-body-oas.yaml"):read("*a")),
          validate_request_body = true,
          validate_response_body = true,
        },
      })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
      admin = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end

      if admin then
        admin:close()
      end
    end)

    describe("request-body", function()
      it("/notify post - requests with no body should pass the validation when operation has no requestBody defined", function()
        local res = assert(client:send {
          method = "POST",
          path = "/notify",
          headers = {
            host = "test1.test",
          },
        })
        assert.response(res).has.status(200)
      end)

      it("/notify post - requests with body should pass the validation when operation has no requestBody defined", function()
        local res = assert(client:send {
          method = "POST",
          path = "/notify",
          headers = {
            host = "test1.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            name = "value",
          }
        })
        assert.response(res).has.status(200)
      end)

      it("should succeed while sending a invalid reqeust body with notify_only_request_validation_failure is set to true", function()
        local res = assert(client:send {
          method = "POST",
          path = "/notify-with-body",
          headers = {
            host = "test2.test",
            ["Content-Type"] = "application/json",
          },
          body = {
            key = 1,
          }
        })
        assert.response(res).has.status(200)
      end)

      describe("should fail with invalid request body", function()
        before_each(function()
          helpers.clean_logfile()
        end)
        local notify_only = { false, true }
        for _, notify in ipairs(notify_only) do
          it("and logs error when notify_only_request_validation_failure=" .. tostring(notify) , function()
            local res = assert(admin:send {
              method = "PATCH",
              path = "/plugins/" .. plugin2.id,
              headers = {
                ["Content-Type"] = "application/json",
              },
              body = {
                config = { notify_only_request_validation_failure = notify, },
              }
            })
            helpers.wait_for_all_config_update({disable_ipv6 = true})
            assert.res_status(200, res)
            res = assert(client:send {
              method = "POST",
              path = "/notify-with-body",
              headers = {
                host = "test2.test",
                ["Content-Type"] = "application/json",
              },
            })
            if notify then
              assert.response(res).has.status(200)
            else
              local body = assert(cjson.decode(assert.res_status(400, res)))
              assert.equal("request param doesn't conform to schema", body.message)
            end

            assert.logfile().has.line("request body validation failed with error")
          end)
        end
      end)

      it("multiple-content-types", function()
        local res = assert(client:send {
          method = "POST",
          path = "/multiple-content-types",
          headers = {
            host = "test3.test",
            ["Content-Type"] = "text/plain",
          },
          body = "hello"
        })
        assert.response(res).has.status(200)
        local body = res:read_body()
        assert.equal("world", body)
        assert.logfile().has.line("request body content-type 'text/plain' is not supported yet, ignore validation")
        assert.logfile().has.line("response body content-type 'text/plain' is not supported yet, ignore validation")
      end)
    end)

    it("spec location by content-type", function()
      local res = assert(client:send {
        method = "POST",
        path = "/content_type_with_charset",
        headers = {
          host = "test1.test",
          ["Content-Type"] = "application/json; charset=utf-8",
        },
        body = {
          key = "hello",
        }
      })
      assert.response(res).has.status(200)

      local res = assert(client:send {
        method = "POST",
        path = "/content_type_with_charset",
        headers = {
          host = "test1.test",
          ["Content-Type"] = "application/json",
        },
        body = {
          key = "hello",
        }
      })
      -- hit the default content-type `*/*` when spec without charset
      local body = cjson.decode(assert.res_status(400, res))
      assert.equal("request body validation failed with error: 'property foo is required'", body.message)

      local res = assert(client:send {
        method = "POST",
        path = "/content_type_without_charset",
        headers = {
          host = "test1.test",
          ["Content-Type"] = "application/json; charset=utf-8",
        },
        body = {
          key = "hello",
        }
      })
      assert.response(res).has.status(200)

      local res = assert(client:send {
        method = "POST",
        path = "/content_type_without_charset",
        headers = {
          host = "test1.test",
          ["Content-Type"] = "application/json",
        },
        body = {
          key = "hello",
        }
      })
      assert.response(res).has.status(200)
    end)
  end)
end
