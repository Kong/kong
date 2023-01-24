---@diagnostic disable: need-check-nil
-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jwe_decryption_schema = require "kong.plugins.jwe-decrypt.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local fmt = string.format

local plugin_name = "jwe-decrypt"

describe(fmt("%s schema - ", plugin_name), function()
  it("accepts valid config options", function()
    local ok, err = v({
      key_sets = {"dummyID"},
    }, jwe_decryption_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("defaults", function()
    local ok, err = v({
      key_sets = {"dummyID"},
    }, jwe_decryption_schema)
    assert.is_nil(err)
    assert.same("Authorization", ok.config.lookup_header_name)
    assert.same("Authorization", ok.config.forward_header_name)
    assert.same(true, ok.config.strict)
  end)

  it("strict", function()
    local ok, err = v({
      key_sets = {"dummyID"},
      strict = false,
    }, jwe_decryption_schema)
    assert.is_nil(err)
    assert.same(false, ok.config.strict)
  end)

  it("forward_header_name", function()
    local ok, err = v({
      key_sets = {"dummyID"},
      forward_header_name = "x1",
    }, jwe_decryption_schema)
    assert.is_nil(err)
    assert.same("x1", ok.config.forward_header_name)
  end)

  it("forward_header_name", function()
    local ok, err = v({
      key_sets = {"dummyID"},
      forward_header_name = "y1",
    }, jwe_decryption_schema)
    assert.is_nil(err)
    assert.same("y1", ok.config.forward_header_name)
  end)
end)
