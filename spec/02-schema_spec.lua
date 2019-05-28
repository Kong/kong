local pre_schema = require "kong.plugins.pre-function.schema"
local v = require("spec.helpers").validate_plugin_config_schema

local mock_fn_one = 'print("hello world!")'
local mock_fn_two = 'local x = 1'
local mock_fn_invalid = 'print('

describe("pre-function schema", function()
  it("validates single function", function()
    local ok, err = v({ functions = { mock_fn_one } }, pre_schema)

    assert.truthy(ok)
    assert.falsy(err)
  end)

  it("validates multiple functions", function()
    local ok, err = v({ functions = { mock_fn_one, mock_fn_two } }, pre_schema)

    assert.truthy(ok)
    assert.falsy(err)
  end)

  describe("errors", function()
    it("with an invalid function", function()
      local ok, err = v({ functions = { mock_fn_invalid } }, pre_schema)

      assert.falsy(ok)
      assert.equals("Error parsing pre-function: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.config.functions)
    end)

    it("with a valid and invalid function", function()
      local ok, err = v({ functions = { mock_fn_one, mock_fn_invalid } }, pre_schema)

      assert.falsy(ok)
      assert.equals("Error parsing pre-function: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.config.functions)
    end)
  end)
end)
