-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "vault-auth"

local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local Schema = require "kong.db.schema"
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  -- load all daos to validate plugin's referenced schemas
  local daos = require("kong.plugins." .. PLUGIN_NAME .. ".daos")
  for _, dao in ipairs(daos) do
    assert(Schema.new(dao))
  end

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()

  it("allows to configure plugin with basic configuration", function()
    local ok, err = validate({
      vault = {
        id = "00000000-0000-0000-0000-000000000000"
      }
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("allows to configure plugin with username format anonymous", function()
    local ok, err = validate({
      vault = {
        id = "00000000-0000-0000-0000-000000000000"
      },
      anonymous = "test"
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
