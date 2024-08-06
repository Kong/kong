-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local schema_def = require "kong.plugins.json-threat-protection.schema"

local v = helpers.validate_plugin_config_schema


describe("Plugin: json-threat-protection (schema)", function()
  it("proper config validates", function()
    local config = {
      max_body_size = 10,
      max_container_depth = 1,
      max_object_entry_count = 2,
      max_object_entry_name_length = 3,
      max_array_element_count = 4,
      max_string_value_length = 5,
      enforcement_mode = "block",
      error_status_code = 400,
      error_message = "BadRequest",
    }
    local ok, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    local error_fields_and_messages = {
      max_body_size = {
        config = {
          max_body_size = 1.2,
        },
        message = "expected an integer",
      },
      max_container_depth = {
        config = {
          max_container_depth = "1",
        },
        message = "expected an integer",
      },
      max_object_entry_count = {
        config = {
          max_object_entry_count = -2,
        },
        message = "value should be between -1 and 2147483648",
      },
      max_object_entry_name_length = {
        config = {
          max_object_entry_name_length = true,
        },
        message = "expected an integer",
      },
      max_array_element_count = {
        config = {
          max_array_element_count = 2^32,
        },
        message = "value should be between -1 and 2147483648",
      },
      max_string_value_length = {
        config = {
          max_string_value_length = "10",
        },
        message = "expected an integer",
      },
      enforcement_mode = {
        config = {
          enforcement_mode = "abc",
        },
        message = "expected one of: block, log_only",
      },
      error_status_code = {
        config = {
          error_status_code = 100,
        },
        message = "value should be between 400 and 499",
      },
      error_message = {
        config = {
          error_message = 123,
        },
        message = "expected a string",
      },
    }

    for name, data in pairs(error_fields_and_messages) do
      it("invalid limit: #" .. name, function()
        local config = data.config
        local ok, err = v(config, schema_def)
        assert.falsy(ok)
        assert.equal(err.config[name], data["message"])
      end)
    end

    it("invalid 0 body size", function()
      local config = {
        max_body_size = 0,
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("max_body_size shouldn't be 0.", err["@entity"][1])
    end)

    it("invalid 0 depth", function()
      local config = {
        max_container_depth = 0,
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("max_container_depth shouldn't be 0.", err["@entity"][1])
    end)
  end)
end)
