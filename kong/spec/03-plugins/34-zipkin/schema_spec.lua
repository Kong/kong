local schema_def = require "kong.plugins.zipkin.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: Zipkin (schema)", function()
  it("rejects repeated tags", function()
    local ok, err = v({
      http_endpoint = "http://example.dev",
      static_tags = {
        { name = "foo", value = "bar" },
        { name = "foo", value = "baz" },
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({
      config = {
        static_tags = "repeated tags are not allowed: foo"
      }
    }, err)
  end)
end)

