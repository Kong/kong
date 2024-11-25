-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local schema_def = require "kong.plugins.injection-protection.schema"

local v = helpers.validate_plugin_config_schema


describe("Plugin: injection-protection (schema)", function()

  it("minimal config validates", function()
    local config = {
    }
    local ok, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  it("minimal config with custom regex validates", function()
    local config = {
      custom_injections = {
        {
          name = "custom",
          regex = "matchthis",
        }
      },
    } 
    local ok, err = v(config, schema_def)
    print(err)
    assert.truthy(ok)

    assert.is_nil(err)
  end)

  it("full config validates", function()
    local config = {

      custom_injections = {
        {
          name = "custom",
          regex = "matchthis",
        },
        {
          name = "hello",
          regex = "world",
        }
      },
      enforcement_mode = "block",
      error_status_code = 400,
      error_message = "Bad Request",
    }
    local ok, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()

    it("invalid custom name", function()
      local config = {
        custom_injections = {
          {
            name = true,
            regex = "matchthis",
          }
        },
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.custom_injections[1].name, "expected a string")
    end)


    it("invalid custom regex", function()
      local config = {
        custom_injections = {
          {
            name = "custom",
            regex = "[a-Z]",
          }
        },
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.custom_injections[1].regex, "not a valid regex: [a-Z]")
    end)




    it("invalid enforcement_mode", function()
      local config = {
        enforcement_mode = "abc",
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.enforcement_mode, "expected one of: block, log_only")
    end)

    it("invalid error_status_code", function()
      local config = {
        error_status_code = 100,
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.error_status_code, "value should be between 400 and 499")
    end)

    it("invalid error_message", function()
      local config = {
        error_message = 123,
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.error_message, "expected a string")
    end)

    it("invalid injection_types", function()
      local config = {
        injection_types = {
          "sql",
          "abc",
        }
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal(err.config.injection_types[2], "expected one of: sql, js, ssi, xpath_abbreviated, xpath_extended, java_exception")
    end)

  end)



end)
