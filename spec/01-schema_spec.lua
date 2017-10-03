local validate_entity      = require("kong.dao.schemas_validation").validate_entity
local forward_proxy_schema = require "kong.plugins.forward-proxy.schema"

describe("forward-proxy schema", function()
  it("accepts a minimal config", function()
    local ok, err = validate_entity({
      proxy_host = "127.0.0.1",
      proxy_port = 12345,
    }, forward_proxy_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("errors with an invalid port (out of bounds)", function()
    local ok, err = validate_entity({
      proxy_host = "127.0.0.1",
      proxy_port = 123456,
    }, forward_proxy_schema)

    assert.is_false(ok)
    assert.same("invalid IP port, value must be between 0 and 2^16",
                err.proxy_port)
  end)

  it("errors with an invalid port (decimal)", function()
    local ok, err = validate_entity({
      proxy_host = "127.0.0.1",
      proxy_port = 12345.6,
    }, forward_proxy_schema)

    assert.is_false(ok)
    assert.same("invalid IP port, value must be an integer",
                err.proxy_port)
  end)

  it("errors with a missing host", function()
    local ok, err = validate_entity({
      proxy_port = 12345,
    }, forward_proxy_schema)

    assert.is_false(ok)
  end)

  it("errors with a missing port", function()
    local ok, err = validate_entity({
      proxy_host = "127.0.0.1",
    }, forward_proxy_schema)

    assert.is_false(ok)
  end)

end)
