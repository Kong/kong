local v = require("spec.helpers").validate_plugin_config_schema

local mock_fn_one = 'print("hello world!")'
local mock_fn_two = 'local x = 1'
local mock_fn_invalid = 'print('

for _, plugin_name in ipairs({ "pre-function", "post-function" }) do

  describe(plugin_name .. " schema", function()

    local schema

    setup(function()
      schema = require("kong.plugins." .. plugin_name .. ".schema")
    end)

    it("validates single function", function()
      local ok, err = v({ functions = { mock_fn_one } }, schema)

      assert.truthy(ok)
      assert.falsy(err)
    end)

    it("validates multiple functions", function()
      local ok, err = v({ functions = { mock_fn_one, mock_fn_two } }, schema)

      assert.truthy(ok)
      assert.falsy(err)
    end)

    describe("errors", function()
      it("with an invalid function", function()
        local ok, err = v({ functions = { mock_fn_invalid } }, schema)

        assert.falsy(ok)
        assert.equals("Error parsing " .. plugin_name .. ": [string \"print(\"]:1: unexpected symbol near '<eof>'", err.config.functions[1])
      end)

      it("with a valid and invalid function", function()
        local ok, err = v({ functions = { mock_fn_one, mock_fn_invalid } }, schema)

        assert.falsy(ok)
        assert.equals("Error parsing " .. plugin_name .. ": [string \"print(\"]:1: unexpected symbol near '<eof>'", err.config.functions[2])
      end)
    end)
  end)

end
