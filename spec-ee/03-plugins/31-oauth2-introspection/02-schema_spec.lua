-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "oauth2-introspection"


local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("allows to configure plugin with basic configuration", function()
    local ok, err = validate({
      introspection_url = "https://example-url.test",
        authorization_value = "Basic MG9hNWlpbjpPcGVuU2VzYW1l"
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("allows to configure plugin with username format anonymous", function()
    local ok, err = validate({
      introspection_url = "https://example-url.test",
      authorization_value = "Basic MG9hNWlpbjpPcGVuU2VzYW1l",
      anonymous = "test"
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
