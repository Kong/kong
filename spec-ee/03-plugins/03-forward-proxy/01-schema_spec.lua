-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local forward_proxy_schema = require "kong.plugins.forward-proxy.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("forward-proxy schema", function()
  it("accepts a minimal config", function()
    local ok, err = v({
      proxy_host = "127.0.0.1",
      proxy_port = 12345,
    }, forward_proxy_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("errors with an invalid port (out of bounds)", function()
    local ok, err = v({
      proxy_host = "127.0.0.1",
      proxy_port = 123456,
    }, forward_proxy_schema)

    assert.is_nil(ok)
    assert.same("value should be between 0 and 65535", err.config.proxy_port)
  end)

  it("errors with an invalid port (decimal)", function()
    local ok, err = v({
      proxy_host = "127.0.0.1",
      proxy_port = 12345.6,
    }, forward_proxy_schema)

    assert.is_nil(ok)
    assert.same("expected an integer", err.config.proxy_port)
  end)

  it("errors with a missing host", function()
    local ok, err = v({
      proxy_port = 12345,
    }, forward_proxy_schema)

    assert.is_nil(ok)
    assert.same("required field missing", err.config.proxy_host)
  end)

  it("errors with a missing port", function()
    local ok, err = v({
      proxy_host = "127.0.0.1",
    }, forward_proxy_schema)

    assert.is_nil(ok)
    assert.same("required field missing", err.config.proxy_port)
  end)

end)
