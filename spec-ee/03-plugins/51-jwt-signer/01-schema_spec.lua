-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = "jwt-signer"
local jwt_signer_schema = require "kong.plugins.jwt-signer.schema"
local fmt = string.format
local v = require("spec.helpers").validate_plugin_config_schema

describe(fmt("%s - schema", plugin_name), function()
  it("defaults", function()
    local ok, err = v({}, jwt_signer_schema)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
end)
