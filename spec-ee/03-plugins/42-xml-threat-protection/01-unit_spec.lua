-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins.xml-threat-protection.schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe("xml-threat-protection: (schema)", function()


  it("gets proper defaults", function()
    local s, err = validate({})
    assert.is_nil(err)
    assert.is_same({
      allow_dtd = false,
      allowed_content_types = {},
      attribute = 1048576,
      bla_max_amplification = 100,
      bla_threshold = 8388608,
      buffer = 1048576,
      checked_content_types = {
        "application/xml"
      },
      comment = 1024,
      document = 10485760,
      entity = 1024,
      entityname = 1024,
      entityproperty = 1024,
      localname = 1024,
      max_attributes = 100,
      max_children = 100,
      max_depth = 50,
      max_namespaces = 20,
      namespace_aware = true,
      namespaceuri = 1024,
      pidata = 1024,
      pitarget = 1024,
      prefix = 1024,
      text = 1048576,
    }, s.config)
  end)


  it("checked content types are accepted", function()
    local ok, err = validate({
      checked_content_types = { "application/json", "*/xml" },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("allowed content types are accepted", function()
    local ok, err = validate({
      allowed_content_types = { "application/json", "*/xml" },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
