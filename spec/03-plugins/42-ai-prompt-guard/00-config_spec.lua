local PLUGIN_NAME = "ai-prompt-guard"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end



describe(PLUGIN_NAME .. ": (schema)", function()

  it("won't allow both allow_patterns and deny_patterns to be unset", function()
    local config = {
      allow_all_conversation_history = true,
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.allow_patterns', 'config.deny_patterns'", err["@entity"][1])
  end)


  it("won't allow both allow_patterns and deny_patterns to be empty arrays", function()
    local config = {
      allow_all_conversation_history = true,
      allow_patterns = {},
      deny_patterns = {},
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.allow_patterns', 'config.deny_patterns'", err["@entity"][1])
  end)


  it("won't allow patterns that are too long", function()
    local config = {
      allow_all_conversation_history = true,
      allow_patterns = {
        [1] = string.rep('x', 501)
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.same({ config = {allow_patterns = { [1] = "length must be at most 500" }}}, err)
  end)


  it("won't allow too many array items", function()
    local config = {
      allow_all_conversation_history = true,
      allow_patterns = {
        [1] = "pattern",
        [2] = "pattern",
        [3] = "pattern",
        [4] = "pattern",
        [5] = "pattern",
        [6] = "pattern",
        [7] = "pattern",
        [8] = "pattern",
        [9] = "pattern",
        [10] = "pattern",
        [11] = "pattern",
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.same({ config = {allow_patterns = "length must be at most 10" }}, err)
  end)

  it("allow_all_conversation_history needs to be false if match_all_roles is set to true", function()
    local config = {
      allow_patterns = { "wat" },
      allow_all_conversation_history = true,
      match_all_roles = true,
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.same({
    ["@entity"] = {
      [1] = 'failed conditional validation given value of field \'config.match_all_roles\'' },
    ["config"] = {
      ["allow_all_conversation_history"] = 'value must be false' }}, err)
  end)

end)
