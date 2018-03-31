local validate_entity = require("kong.dao.schemas_validation").validate_entity
local pre_schema = require "kong.plugins.pre-function.schema"

local mock_fn_one = 'print("hello world!")'
local mock_fn_two = 'local x = 1'
local mock_fn_invalid = 'print('

describe("pre-function schema", function()
  it("validates single function", function()
    local ok, err = validate_entity({ functions = { mock_fn_one } }, pre_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  it("validates multiple functions", function()
    local ok, err = validate_entity({ functions = { mock_fn_one, mock_fn_two } }, pre_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("with an invalid function", function()
      local ok, _, err = validate_entity({ functions = { mock_fn_invalid } }, pre_schema)

      assert.False(ok)
      assert.equals("Error parsing pre-function #1: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.message)
    end)

    it("with a valid and invalid function", function()
      local ok, _, err = validate_entity({ functions = { mock_fn_one, mock_fn_invalid } }, pre_schema)

      assert.False(ok)
      assert.equals("Error parsing pre-function #2: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.message)
    end)
  end)
end)
