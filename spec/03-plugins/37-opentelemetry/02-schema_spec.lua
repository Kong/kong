local schema_def = require "kong.plugins.opentelemetry.schema"
local validate_plugin_config_schema = require "spec.helpers".validate_plugin_config_schema

describe("Plugin: OpenTelemetry (schema)", function()
  it("rejects invalid attribute keys", function()
    local ok, err = validate_plugin_config_schema({
      endpoint = "http://example.dev",
      resource_attributes = {
        [123] = "",
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({
      config = {
        resource_attributes = "expected a string"
      }
    }, err)
  end)

  it("rejects invalid attribute values", function()
    local ok, err = validate_plugin_config_schema({
      endpoint = "http://example.dev",
      resource_attributes = {
        foo = "",
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({
      config = {
        resource_attributes = "length must be at least 1"
      }
    }, err)
  end)
end)
