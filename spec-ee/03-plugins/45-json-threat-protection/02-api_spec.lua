-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson   = require "cjson"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: json-threat-protection (API) [#" .. strategy .. "]", function()
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
          plugins    = "bundled,json-threat-protection",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      lazy_teardown(function()
        if admin_client then
          admin_client:close()
        end

        helpers.stop_kong()
      end)

      it("should create plugin instance successfully with negative value", function()
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
      end)
    end)

    describe("POST", function()
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
          plugins    = "bundled,json-threat-protection",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      it("should save with proper config", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "json-threat-protection",
            route = { id = route.id },
            config = {
              max_container_depth = 1,
              max_object_entry_count = 2,
              max_object_entry_name_length = 3,
              max_array_element_count = 4,
              max_string_value_length = 5,
              enforcement_mode = "block",
              error_status_code = 400,
              error_message = "BadRequest",
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal(1, body.config.max_container_depth)
      end)

      it("should not save with wrong config", function()
        local error_config_and_expect_result = {
          {
            config = {
              max_container_depth = "1",
            },
            result = {
              code = 2,
              fields = {
                ["@entity"] = { "max_container_depth shouldn't be 0." },
                config = {
                  max_container_depth = "expected an integer"
                }
              },
              message = "2 schema violations (max_container_depth shouldn't be 0.; config.max_container_depth: expected an integer)",
              name = "schema violation",
            }
          },
          {
            config = {
              max_body_size = "2",
            },
            result = {
              code = 2,
              fields = {
                ["@entity"] = { "max_body_size shouldn't be 0." },
                config = {
                  max_body_size = "expected an integer"
                }
              },
              message = "2 schema violations (max_body_size shouldn't be 0.; config.max_body_size: expected an integer)",
              name = "schema violation",
            },
          },
          {
            config = {
              max_object_entry_count = 1.2,
            },
            result = {
              code = 2,
              fields = {
                config = {
                  max_object_entry_count = "expected an integer"
                }
              },
              message = "schema violation (config.max_object_entry_count: expected an integer)",
              name = "schema violation",
            },
          },
          {
            config = {
              max_object_entry_name_length = -2,
            },
            result = {
              code = 2,
              fields = {
                config = {
                  max_object_entry_name_length = "value should be between -1 and 2147483648",
                }
              },
              message = "schema violation (config.max_object_entry_name_length: value should be between -1 and 2147483648)",
              name = "schema violation",
            },
          },
          {
            config = {
              max_array_element_count = {},
            },
            result = {
              code = 2,
              fields = {
                config = {
                  max_array_element_count = "expected an integer"
                }
              },
              message = "schema violation (config.max_array_element_count: expected an integer)",
              name = "schema violation",
            },
          },
          {
            config = {
              max_string_value_length = "-1",
            },
            result = {
              code = 2,
              fields = {
                config = {
                  max_string_value_length = "expected an integer"
                }
              },
              message = "schema violation (config.max_string_value_length: expected an integer)",
              name = "schema violation",
            },
          },
          {
            config = {
              enforcement_mode = true,
            },
            result = {
              code = 2,
              fields = {
                config = {
                  enforcement_mode = "expected a string"
                }
              },
              message = "schema violation (config.enforcement_mode: expected a string)",
              name = "schema violation",
            },
          },
          {
            config = {
              error_status_code = 500,
            },
            result = {
              code = 2,
              fields = {
                config = {
                  error_status_code = "value should be between 400 and 499"
                }
              },
              message = "schema violation (config.error_status_code: value should be between 400 and 499)",
              name = "schema violation",
            },
          },
          {
            config = {
              error_message = 123,
            },
            result = {
              code = 2,
              fields = {
                config = {
                  error_message = "expected a string"
                }
              },
              message = "schema violation (config.error_message: expected a string)",
              name = "schema violation",
            },
          },
        }

        for _, conf in ipairs(error_config_and_expect_result) do
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "json-threat-protection",
              route = { id = route.id },
              config = conf.config
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same(conf.result, json)
        end
      end)
    end)
  end)
end

