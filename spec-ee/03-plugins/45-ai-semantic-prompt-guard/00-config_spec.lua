-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "ai-semantic-prompt-guard"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end



describe(PLUGIN_NAME .. ": (schema)", function()

  it("won't allow both allow_prompts and deny_prompts to be unset", function()
    local config = {
        embeddings = {
            model = {
                provider = "openai",
                name = "text-embedding-3-large",
            },
        },
        vectordb = {
            strategy = "redis",
            distance_metric = "cosine",
            threshold = 0.5,
            dimensions = 1024,
            redis = {
                host = "localhost",
                port = 6379,
            },
        },
        rules = {
            match_all_conversation_history = true,
        }
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.rules.allow_prompts', 'config.rules.deny_prompts'", err["@entity"][1])
  end)


  it("won't allow both allow_patterns and deny_patterns to be empty arrays", function()
    local config = {
        embeddings = {
            model = {
                provider = "openai",
                name = "text-embedding-3-large",
            },
        },
        vectordb = {
            strategy = "redis",
            distance_metric = "cosine",
            threshold = 0.5,
            dimensions = 1024,
            redis = {
                host = "localhost",
                port = 6379,
            },
        },
        rules = {
            match_all_conversation_history = true,
            allow_prompts = {},
            deny_prompts = {},
        }
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.equal("at least one of these fields must be non-empty: 'config.rules.allow_prompts', 'config.rules.deny_prompts'", err["@entity"][1])
  end)


  it("won't allow patterns that are too long", function()
    local config = {
        embeddings = {
            model = {
                provider = "openai",
                name = "text-embedding-3-large",
            },
        },
        vectordb = {
            strategy = "redis",
            distance_metric = "cosine",
            threshold = 0.5,
            dimensions = 1024,
            redis = {
                host = "localhost",
                port = 6379,
            },
        },
        rules = {
            match_all_conversation_history = true,
            allow_prompts = {
                [1] = string.rep('x', 501)
            },
            deny_prompts = {},
        }
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.same({ config = { rules = {allow_prompts = { [1] = "length must be at most 500" }}}}, err)
  end)

  it("openai embedding not allow custome_url", function()
    local config = {
        embeddings = {
            model = {
                provider = "openai",
                name = "text-embedding-3-large",
                options = {
                    upstream_url = "http://localhost:8000",
                },
            },
        },
        vectordb = {
            strategy = "redis",
            distance_metric = "cosine",
            threshold = 0.5,
            dimensions = 1024,
            redis = {
                host = "localhost",
                port = 6379,
            },
        },
        rules = {
            match_all_conversation_history = true,
            allow_prompts = {
                [1] = string.rep('x', 501)
            },
            deny_prompts = {},
        }
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.not_nil(err)
    assert.same({ config = { rules = {allow_prompts = { [1] = "length must be at most 500" }}}}, err)
  end)
end)
