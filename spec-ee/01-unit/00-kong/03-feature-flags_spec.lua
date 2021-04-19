-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local feature_flags = require "kong.enterprise_edition.feature_flags"


describe("Feature Flags", function()
  it("loads feature flags from a feature conf file", function()
    local ok, err = feature_flags.init("spec-ee/fixtures/mock_feature_flags.conf")
    assert.True(ok)
    assert.is_nil(err)

    local foo_enabled = feature_flags.is_enabled("foo")
    assert.same(true, foo_enabled)

    local baz_disabled = feature_flags.is_enabled("baz")
    assert.same(false, baz_disabled)

    local unknown_flag = feature_flags.is_enabled("unknown_flag")
    assert.same(false, unknown_flag)

    local bar_value, err = feature_flags.get_feature_value("bar_value")
    assert.is_nil(err)
    assert.same(42, bar_value)
  end)

  it("throws an error if a value does not exist", function()
    local ok, err = feature_flags.init("spec-ee/fixtures/mock_feature_flags.conf")
    assert.True(ok)
    assert.is_nil(err)

    local value, err = feature_flags.get_feature_value("does_not_exists")
    assert.is_not_nil(err)
    assert.is_nil(value)
  end)

  it("throws error if file does not exist", function()
    local ok, err = feature_flags.init("spec/fixtures/does_not_exists.conf")
    assert.False(ok)
    assert.is_not_nil(err)
  end)
  it("does not split comma separated value", function()
    local ok, err = feature_flags.init("spec-ee/fixtures/mock_feature_flags.conf")
    assert.True(ok)
    assert.is_nil(err)

    local value, err = feature_flags.get_feature_value("multi")
    assert.is_nil(err)
    assert.same("kong,strong", value)
  end)
end)
