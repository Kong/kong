local PLUGIN_NAME = "ai-proxy"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


local SELF_HOSTED_MODELS = {
  "mistral",
  "llama2",
}


describe(PLUGIN_NAME .. ": (schema)", function()


  for i, v in ipairs(SELF_HOSTED_MODELS) do
    local op = it
    if v == "mistral" then -- mistral.ai now has managed service too!
      op = pending
    end
    op("requires upstream_url when using self-hosted " .. v .. " model", function()
      local config = {
        route_type = "llm/v1/chat",
        auth = {
          header_name = "Authorization",
          header_value = "Bearer token",
        },
        model = {
          name = "llama-2-7b-chat-hf",
          provider = v,
          options = {
            max_tokens = 256,
            temperature = 1.0,
          },
        },
      }

      if v == "llama2" then
        config.model.options.llama2_format = "raw"
      end

      if v == "mistral" then
        config.model.options.mistral_format = "ollama"
      end

      local ok, err = validate(config)

      assert.not_nil(err["config"]["@entity"])
      assert.not_nil(err["config"]["@entity"][1])
      assert.equal(err["config"]["@entity"][1], "must set 'model.options.upstream_url' for self-hosted providers/models")
      assert.is_falsy(ok)
    end)

    it("does not require API auth for self-hosted " .. v .. " model", function()
      local config = {
        route_type = "llm/v1/chat",
        model = {
          name = "llama-2-7b-chat-hf",
          provider = v,
          options = {
            max_tokens = 256,
            temperature = 1.0,
            upstream_url = "http://nowhere",
          },
        },
      }

      if v == "llama2" then
        config.model.options.llama2_format = "raw"
      end

      if v == "mistral" then
        config.model.options.mistral_format = "ollama"
      end

      local ok, err = validate(config)

      assert.is_truthy(ok)
      assert.is_falsy(err)
    end)
  end

  it("requires [anthropic_version] field when anthropic provider is used", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "x-api-key",
        header_value = "anthropic_key",
      },
      model = {
        name = "anthropic-chat",
        provider = "anthropic",
        options = {
          max_tokens = 256,
          temperature = 1.0,
        },
      },
    }

    local ok, err = validate(config)

    assert.not_nil(err["config"]["@entity"])
    assert.not_nil(err["config"]["@entity"][1])
    assert.equal(err["config"]["@entity"][1], "must set 'model.options.anthropic_version' for anthropic provider")
    assert.is_falsy(ok)
  end)

  it("do not support log statistics when /chat route_type is used for anthropic provider", function()
    local config = {
      route_type = "llm/v1/completions",
      auth = {
        header_name = "x-api-key",
        header_value = "anthropic_key",
      },
      model = {
        name = "anthropic-chat",
        provider = "anthropic",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          anthropic_version = "2021-09-01",
        },
      },
      logging = {
        log_statistics = true,
      },
    }

    local ok, err = validate(config)
    assert.is_falsy(ok)
    assert.not_nil(err["config"]["@entity"])
    assert.not_nil(err["config"]["@entity"][1])
    assert.not_nil(err["config"]["@entity"][1], "anthropic does not support statistics when route_type is llm/v1/completions")
  end)

  it("requires [azure_instance] field when azure provider is used", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        name = "azure-chat",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
        },
      },
    }

    local ok, err = validate(config)

    assert.not_nil(err["config"]["@entity"])
    assert.not_nil(err["config"]["@entity"][1])
    assert.equal(err["config"]["@entity"][1], "must set 'model.options.azure_instance' for azure provider")
    assert.is_falsy(ok)
  end)

  it("requires both [config.auth.header_name] and [config.auth.header_value] to be set", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
      },
      model = {
        name = "openai",
        provider = "openai",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.equals(err["config"]["@entity"][1], "all or none of these fields must be set: 'auth.header_name', 'auth.header_value'")
    assert.is_falsy(ok)
  end)

  it("requires both [config.auth.header_name] and [config.auth.header_value] to be set", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        name = "openai",
        provider = "openai",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(err)
    assert.is_truthy(ok)
  end)

  it("requires all of [config.auth.param_name] and [config.auth.param_value] and [config.auth.param_location] to be set", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        param_name = "apikey",
        param_value = "key",
      },
      model = {
        name = "openai",
        provider = "openai",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.equals(err["config"]["@entity"][1], "all or none of these fields must be set: 'auth.param_name', 'auth.param_value', 'auth.param_location'")
  end)

  it("requires all of [config.auth.param_name] and [config.auth.param_value] and [config.auth.param_location] to be set", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        param_name = "apikey",
        param_value = "key",
        param_location = "query",
      },
      model = {
        name = "openai",
        provider = "openai",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(err)
    assert.is_truthy(ok)
  end)

  it("requires all auth parameters set in order to use both header and param types", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        param_name = "apikey",
        param_value = "key",
        param_location = "query",
        header_name = "Authorization",
        header_value = "Bearer token"
      },
      model = {
        name = "openai",
        provider = "openai",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(err)
    assert.is_truthy(ok)
  end)

  it("bedrock model can not support ath.allowed_auth_override", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        param_name = "apikey",
        param_value = "key",
        param_location = "query",
        header_name = "Authorization",
        header_value = "Bearer token",
        allow_override = true,
      },
      model = {
        name = "bedrock",
        provider = "bedrock",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("gemini model can not support ath.allowed_auth_override", function()
    local config = {
      route_type = "llm/v1/chat",
      auth = {
        param_name = "apikey",
        param_value = "key",
        param_location = "query",
        header_name = "Authorization",
        header_value = "Bearer token",
        allow_override = true,
      },
      model = {
        name = "gemini",
        provider = "gemini",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          upstream_url = "http://nowhere",
        },
      },
    }

    local ok, err = validate(config)

    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)
end)
