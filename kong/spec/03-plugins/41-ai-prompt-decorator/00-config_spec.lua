local PLUGIN_NAME = "ai-prompt-decorator"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end

describe(PLUGIN_NAME .. ": (schema)", function()
  it("won't allow empty config object", function()
    local config = {
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.prompts.prepend', 'config.prompts.append'", err["@entity"][1])
  end)

  it("won't allow both head and tail to be unset", function()
    local config = {
      prompts = {},
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.prompts.prepend', 'config.prompts.append'", err["@entity"][1])
  end)

  it("won't allow both allow_patterns and deny_patterns to be empty arrays", function()
    local config = {
      prompts = {
        prepend = {},
        append = {},
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.prompts.prepend', 'config.prompts.append'", err["@entity"][1])
  end)

  it("allows prepend only", function()
    local config = {
      prompts = {
        prepend = {
          [1] = {
            role = "system",
            content = "Prepend text 1 here.",
          },
        },
        append = {},
      },
    }

    local ok, err = validate(config)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("allows append only", function()
    local config = {
      prompts = {
        prepend = {},
        append = {
          [1] = {
            role = "system",
            content = "Prepend text 1 here.",
          },
        },
      },
    }

    local ok, err = validate(config)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)
