-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  for _, mode in ipairs({"block", "log_only"}) do
    for _, max_body_size in ipairs({-1, 1024 * 1024 * 2}) do
      describe("Plugin: json-threat-protection (integration) #" .. strategy, function()
        describe("#" .. mode .. " mode with max_body_size: " .. tostring(max_body_size), function()
          local proxy_client
          local admin_client
          local bp
      
          lazy_setup(function()
            bp = helpers.get_db_utils(nil, {
              "routes",
              "services",
              "plugins",
            })

            local service = bp.services:insert()

            local route = bp.routes:insert {
              paths      = { "/" },
              hosts      = { "test1.test" },
              protocols  = { "http", "https" },
              service    = service
            }

            assert(helpers.start_kong({
              database   = strategy,
              log_level  = "warn",
              plugins    = "bundled,json-threat-protection",
              nginx_conf = "spec/fixtures/custom_nginx.template",
            }))

            admin_client = helpers.admin_client()
            proxy_client = helpers.proxy_client()

            local res = assert(admin_client:send {
              method  = "POST",
              path    = "/plugins",
              body    = {
                name  = "json-threat-protection",
                route = { id = route.id },
                config = {
                  max_body_size = max_body_size,
                  max_container_depth = 2,
                  max_object_entry_count = 2,
                  max_object_entry_name_length = 3,
                  max_array_element_count = 2,
                  max_string_value_length = 3,
                  enforcement_mode = mode,
                  error_status_code = 400,
                  error_message = "Custom Error Message",
                },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = cjson.decode(assert.res_status(201, res))
            assert.equal(2, body.config.max_container_depth)

            helpers.wait_for_all_config_update()
          end)
      
          lazy_teardown(function()
            if proxy_client then
              proxy_client:close()
            end

            if admin_client then
              admin_client:close()
            end
      
            helpers.stop_kong()
          end)
      
          it("should be on success", function()
            local res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = cjson.encode({
                aaa = 1,
                bbb = "abc",
              }),
            })
            assert.response(res).has.status(200)
          end)

          describe("too deep container depth", function()
            it("nested too deep", function()
              local res = assert(proxy_client:send {
                method  = "POST",
                path    = "/",
                headers = {
                  ["Host"]   = "test1.test",
                  ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                  aaa = 1,
                  bbb = {
                    ccc = {
                      1, 2, {
                        3, 4,
                      },
                    },
                  },
                }),
              })
              if mode == "block" then
                assert.response(res).has.status(400)
                local body = res:read_body()
                assert.equal("Custom Error Message", cjson.decode(body)["message"])

              else
                assert.response(res).has.status(200)
                assert.logfile().has.line("The maximum allowed nested depth is exceeded", true)
              end
            end)

            it("too many elements in array", function()
              local res = assert(proxy_client:send {
                method  = "GET",
                path    = "/",
                headers = {
                  ["Host"]   = "test1.test",
                  ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                  aaa = 1,
                  bbb = {1, 2, 3},
                }),
              })
              if mode == "block" then
                assert.response(res).has.status(400)
                local body = res:read_body()
                assert.equal("Custom Error Message", cjson.decode(body)["message"])

              else
                assert.response(res).has.status(200)
                assert.logfile().has.line("The maximum number of elements allowed in an array is exceeded", true)
              end
            end)

            it("too many object entries", function()
              local res = assert(proxy_client:send {
                method  = "GET",
                path    = "/",
                headers = {
                  ["Host"]   = "test1.test",
                  ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                  aaa = 1,
                  bbb = "abc",
                  ccc = true,
                }),
              })
              if mode == "block" then
                assert.response(res).has.status(400)
                local body = res:read_body()
                assert.equal("Custom Error Message", cjson.decode(body)["message"])

              else
                assert.response(res).has.status(200)
                assert.logfile().has.line("The maximum number of entries allowed in an object is exceeded", true)
              end
            end)

            it("key too long", function()
              local res = assert(proxy_client:send {
                method  = "GET",
                path    = "/",
                headers = {
                  ["Host"]   = "test1.test",
                  ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                  aaa = 1,
                  bbbb = "abc",
                }),
              })
              if mode == "block" then
                assert.response(res).has.status(400)
                local body = res:read_body()
                assert.equal("Custom Error Message", cjson.decode(body)["message"])

              else
                assert.response(res).has.status(200)
                assert.logfile().has.line("The maximum string length allowed in an object's entry name is exceeded", true)
              end
            end)

            it("string too long", function()
              local res = assert(proxy_client:send {
                method  = "GET",
                path    = "/",
                headers = {
                  ["Host"]   = "test1.test",
                  ["Content-Type"] = "application/json",
                },
                body = cjson.encode({
                  aaa = 1,
                  bbb = string.rep("A", 1024 * 1024),
                }),
              })
              if mode == "block" then
                assert.response(res).has.status(400)
                local body = res:read_body()
                assert.equal("Custom Error Message", cjson.decode(body)["message"])

              else
                assert.response(res).has.status(200)
                assert.logfile().has.line("The maximum length allowed for a string value is exceeded", true)
              end
            end)
          end)
        end)
      end)
    end
  end
end
