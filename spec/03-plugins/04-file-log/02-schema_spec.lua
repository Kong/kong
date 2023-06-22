-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "file-log"
local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")
local validate_entity = require("spec.helpers").validate_plugin_config_schema

local validate do
  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe("Plugin: file-log (schema)", function()

  local tests = {
    {
      name = "path is required",
      input = {
        reopen = true
      },
      error = {
        config = {
          path = "required field missing"
        }
      }
    },
    ----------------------------------------
    {
      name = "rejects invalid filename",
      input = {
        path = "/ovo*",
        reopen = true
      },
      error = {
        config = {
          path = "not a valid filename"
        }
      }
    },
    ----------------------------------------
    {
      name = "accepts valid filename",
      input = {
        path = "/tmp/log.txt",
        reopen = true
      },
      error = nil,
    },
    ----------------------------------------
    {
      name = "accepts custom fields set by lua code",
      input = {
        path = "/tmp/log.txt",
        custom_fields_by_lua = {
          foo = "return 'bar'",
        }
      },
      error = nil,
    },
  }

  for _, t in ipairs(tests) do
    it(t.name, function()
      local output, err = validate(
        t.input
      )
      assert.same(t.error, err)
      if not t.error then
        assert.is_truthy(output)
      end
    end)
  end
end)
