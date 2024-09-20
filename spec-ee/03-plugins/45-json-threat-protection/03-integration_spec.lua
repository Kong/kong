-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local MAX_CONTAINER_DEPTH = 2
local MAX_OBJECT_ENTRY_COUNT = 2
local MAX_OBJECT_ENTRY_NAME_LENGTH = 3
local MAX_ARRAY_ELEMENT_COUNT = 2
local MAX_STRING_VALUE_LENGTH = 3
local CUSTOME_ERROR_MESSAGE = "Custom Error Message"

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
                  max_container_depth = MAX_CONTAINER_DEPTH,
                  max_object_entry_count = MAX_OBJECT_ENTRY_COUNT,
                  max_object_entry_name_length = MAX_OBJECT_ENTRY_NAME_LENGTH,
                  max_array_element_count = MAX_ARRAY_ELEMENT_COUNT,
                  max_string_value_length = MAX_STRING_VALUE_LENGTH,
                  enforcement_mode = mode,
                  error_status_code = 400,
                  error_message = CUSTOME_ERROR_MESSAGE,
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

          it("count string length in utf-8 characters", function()
            -- if this assertion fails, it means that the `MAX_STRING_VALUE_LENGTH` has been changed
            -- and this test should be updated accordingly
            assert(MAX_STRING_VALUE_LENGTH == 3, "MAX_STRING_VALUE_LENGTH should be 3 for this test")
            local res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = [["😀😀😀"]]  -- MAX_STRING_VALUE_LENGTH is 3,
                                  -- but this string has not only 3 bytes,
                                  -- this plugin counts length in utf-8 characters
                                  -- so this request should be successful
            })
            assert.response(res).has.status(200)

            res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = [["\u0031\u0031\u0031"]]  -- MAX_STRING_VALUE_LENGTH is 3,
                                              -- but this string has not only 3 bytes,
                                              -- this plugin counts length in utf-8 characters
                                              -- so this request should be successful
            })
            assert.response(res).has.status(200)
          end)

          it("count key length in utf-8 characters", function()
            -- if this assertion fails, it means that the `MAX_OBJECT_ENTRY_NAME_LENGTH` has been changed
            -- and this test should be updated accordingly
            assert(MAX_OBJECT_ENTRY_NAME_LENGTH == 3, "MAX_OBJECT_ENTRY_NAME_LENGTH should be 3 for this test")
            local res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = [[{
                "😀😀😀": 0
              }]]    -- MAX_OBJECT_ENTRY_NAME_LENGTH is 3,
                     -- but this string has not only 3 bytes,
                     -- this plugin counts length in utf-8 characters
                     -- so this request should be successful
            })
            assert.response(res).has.status(200)

            res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = [[{
                "\u0031\u0031\u0031": 0
              }]],   -- MAX_OBJECT_ENTRY_NAME_LENGTH is 3,
                     -- but this string has not only 3 bytes,
                     -- this plugin counts length in utf-8 characters
                     -- so this request should be successful
            })
            assert.response(res).has.status(200)
          end)

          it("reject non utf-8 input", function()
            local res = assert(proxy_client:send {
              method  = "POST",
              path    = "/",
              headers = {
                ["Host"]   = "test1.test",
                ["Content-Type"] = "application/json",
              },
              body = string.rep(string.char(147), 8),
            })
            assert.response(res).has.status(400)
            assert.logfile().has.line("Non-UTF8 input", true)
          end)

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
              assert.equal(CUSTOME_ERROR_MESSAGE, cjson.decode(body)["message"])

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
              assert.equal(CUSTOME_ERROR_MESSAGE, cjson.decode(body)["message"])

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
              assert.equal(CUSTOME_ERROR_MESSAGE, cjson.decode(body)["message"])

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
              assert.equal(CUSTOME_ERROR_MESSAGE, cjson.decode(body)["message"])

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
              assert.equal(CUSTOME_ERROR_MESSAGE, cjson.decode(body)["message"])

            else
              assert.response(res).has.status(200)
              assert.logfile().has.line("The maximum length allowed for a string value is exceeded", true)
            end
          end)
        end)
      end)
    end
  end

  describe("with default config", function()
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
          config = {},
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(201, res))
      assert.equal(8192, body.config.max_body_size)
      assert.equal(-1, body.config.max_container_depth)
      assert.equal(-1, body.config.max_object_entry_count)
      assert.equal(-1, body.config.max_object_entry_name_length)
      assert.equal(-1, body.config.max_array_element_count)
      assert.equal(-1, body.config.max_string_value_length)
      assert.equal("block", body.config.enforcement_mode)
      assert.equal(400, body.config.error_status_code)
      assert.equal("Bad Request", body.config.error_message)

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
  end)
end
