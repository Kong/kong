local schema_def = require "kong.plugins.rate-limiting.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: basic-rate-limiting (schema)", function()
  it("proper config validates", function()
    local config = { minute = 10 }
    local ok, _, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)
end)
