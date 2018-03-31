local validate_entity = require("kong.dao.schemas_validation").validate_entity
local post_schema = require "kong.plugins.post-function.schema"

local mock_fn_one = 'print("hello world!")'
local mock_fn_two = 'local x = 1'
local mock_fn_invalid = 'print('

describe("post-function schema", function()
  it("validates single function", function()
    local ok, err = validate_entity({ functions = { mock_fn_one } }, post_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  it("validates multiple functions", function()
    local ok, err = validate_entity({ functions = { mock_fn_one, mock_fn_two } }, post_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("with an invalid function", function()
      local ok, _, err = validate_entity({ functions = { mock_fn_invalid } }, post_schema)

      assert.False(ok)
      assert.equals("Error parsing post-function #1: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.message)
    end)

    it("with a valid and invalid function", function()
      local ok, _, err = validate_entity({ functions = { mock_fn_one, mock_fn_invalid } }, post_schema)

      assert.False(ok)
      assert.equals("Error parsing post-function #2: [string \"print(\"]:1: unexpected symbol near '<eof>'", err.message)
    end)
  end)
end)
