local schema_def = require "kong.plugins.request-transformer.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: request-transformer (schema)", function()
  it("validates http_method", function()
    local ok, err = v({ http_method = "GET" }, schema_def)
    assert.truthy(ok)
    assert.falsy(err)
  end)
  it("errors invalid http_method", function()
    local ok, err = v({ http_method = "HELLO!" }, schema_def)
    assert.falsy(ok)
    assert.equal("invalid value: HELLO!", err.config.http_method)
  end)
end)
