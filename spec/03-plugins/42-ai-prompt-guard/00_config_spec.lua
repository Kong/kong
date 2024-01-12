local PLUGIN_NAME = "ai-prompt-guard"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

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
    assert.equal("must set one item in either [allow_patterns] or [deny_patterns]", err["@entity"][1])
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
    assert.equal("must set one item in either [allow_patterns] or [deny_patterns]", err["@entity"][1])
  end)
end)
