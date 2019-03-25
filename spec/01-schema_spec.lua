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
