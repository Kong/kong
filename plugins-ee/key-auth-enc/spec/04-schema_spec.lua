-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils   = require "kong.tools.utils"
local key_auth_enc_schema = require "kong.plugins.key-auth-enc.schema"
local v = require("spec.helpers").validate_plugin_config_schema

-- FTI-3328
describe("key-auth-enc schema", function()
  it("accepts uuid for anonymous user", function()
    local uuid = utils.uuid()
    local ok, err = v({
        key_names = { "apikey" },
        anonymous = uuid,
    }, key_auth_enc_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts arbitrary strings for anonymous user", function()
    local username = "alice"  -- do not need an existing anonymous username
    local ok, err = v({
        key_names = { "apikey" },
        anonymous = username,
    }, key_auth_enc_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
