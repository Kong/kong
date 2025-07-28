local PLUGIN_NAME = "ai-proxy"
local pl_file = require("pl.file")
local pl_replace = require("pl.stringx").replace
local cjson = require("cjson.safe")
local fmt = string.format
local llm = require("kong.llm")
local ai_shared = require("kong.llm.drivers.shared")

local SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_URL = {
  messages = {
    {
      role = "user",
      content = {
        {
          type = "text",
          text = "What is in this picture?",
        },
        {
          type = "image_url",
          image_url = {
            url = "https://example.local/image.jpg",
          },
        },
      },
    },
    {
      role = "assistant",
      content = {
        {
          type = "text",
          text = "A picture of a cat.",
        },
      },
    },
    {
      role = "user",
      content = {
        {
          type = "text",
          text = "Now draw it wearing a party-hat.",
        },
      },
    },
  }
}

local SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_B64 = {
  messages = {
    {
      role = "user",
      content = {
        {
          type = "text",
          text = "What is in this picture?",
        },
        {
          type = "image_url",
          image_url = {
            url = "data:image/png;base64,Y2F0X3BuZ19oZXJlX2xvbAo=",
          },
        },
      },
    },
    {
      role = "assistant",
      content = {
        {
          type = "text",
          text = "A picture of a cat.",
        },
      },
    },
    {
      role = "user",
      content = {
        {
          type = "text",
          text = "Now draw it wearing a party-hat.",
        },
      },
    },
  }
}

local SAMPLE_LLM_V1_CHAT = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "assistant",
      content = "What is 1 + 1?"
    },
  },
}

local SAMPLE_LLM_V1_CHAT_WITH_SOME_OPTS = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "assistant",
      content = "What is 1 + 1?"
    },
  },
  max_tokens = 256,
  temperature = 0.1,
  top_p = 0.2,
  some_extra_param = "string_val",
  another_extra_param = 0.5,
}

local SAMPLE_LLM_V1_CHAT_WITH_GUARDRAILS = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "assistant",
      content = "What is 1 + 1?"
    },
  },
  guardrailConfig = {
    guardrailIdentifier = "yu5xwvfp4sud",
    guardrailVersion = "1",
    trace = "enabled",
  },
}

local SAMPLE_DOUBLE_FORMAT = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "assistant",
      content = "What is 1 + 1?"
    },
  },
  prompt = "Hi world",
}

local SAMPLE_OPENAI_TOOLS_REQUEST = {
  messages = {
    [1] = {
      role = "user",
      content = "Is the NewPhone in stock?"
    },
  },
  tools = {
    [1] = {
      ['function'] = {
        parameters = {
          ['type'] = "object",
          properties = {
            product_name = {
              ['type'] = "string",
            },
          },
          required = {
            "product_name",
          },
        },
        name = "check_stock",
        description = "Check a product is in stock."
      },
      ['type'] = "function",
    },
  },
}

local SAMPLE_GEMINI_TOOLS_RESPONSE = {
  candidates = { {
    content = {
      role = "model",
      parts = { {
        functionCall = {
          name = "sql_execute",
          args = {
            product_name = "NewPhone"
          }
        }
      } }
    },
    finishReason = "STOP",
  } },
}

local SAMPLE_BEDROCK_TOOLS_RESPONSE = {
  metrics = {
    latencyMs = 3781
  },
  output = {
    message = {
      content = { {
        text = "Certainly! To calculate the sum of 121, 212, and 313, we can use the \"sumArea\" function that's available to us."
      }, {
        toolUse = {
          input = {
            areas = { 121, 212, 313 }
          },
          name = "sumArea",
          toolUseId = "tooluse_4ZakZPY9SiWoKWrAsY7_eg"
        }
      } },
      role = "assistant"
    }
  },
  stopReason = "tool_use",
  usage = {
    inputTokens = 410,
    outputTokens = 115,
    totalTokens = 525
  }
}

local FORMATS = {
  openai = {
    ["llm/v1/chat"] = {
      config = {
        name = "gpt-4",
        provider = "openai",
        options = {
          max_tokens = 512,
          temperature = 0.5,
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "gpt-3.5-turbo-instruct",
        provider = "openai",
        options = {
          max_tokens = 512,
          temperature = 0.5,
        },
      },
    },
  },
  cohere = {
    ["llm/v1/chat"] = {
      config = {
        name = "command",
        provider = "cohere",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 1.0
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "command",
        provider = "cohere",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 0.75,
          top_k = 5,
        },
      },
    },
  },
  anthropic = {
    ["llm/v1/chat"] = {
      config = {
        name = "claude-2.1",
        provider = "anthropic",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 1.0,
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "claude-2.1",
        provider = "anthropic",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 1.0,
        },
      },
    },
  },
  azure = {
    ["llm/v1/chat"] = {
      config = {
        name = "gpt-4",
        provider = "azure",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 1.0,
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "gpt-3.5-turbo-instruct",
      provider = "azure",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          top_p = 1.0,
        },
      },
    },
  },
  llama2_raw = {
    ["llm/v1/chat"] = {
      config = {
        name = "llama2",
        provider = "llama2",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          llama2_format = "raw",
          top_p = 1,
          top_k = 40,
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "llama2",
        provider = "llama2",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          llama2_format = "raw",
        },
      },
    },
  },
  llama2_ollama = {
    ["llm/v1/chat"] = {
      config = {
        name = "llama2",
        provider = "llama2",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          llama2_format = "ollama",
        },
      },
    },
    ["llm/v1/completions"] = {
      config = {
        name = "llama2",
        provider = "llama2",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          llama2_format = "ollama",
        },
      },
    },
  },
  mistral_openai = {
    ["llm/v1/chat"] = {
      config = {
        name = "mistral-tiny",
        provider = "mistral",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          mistral_format = "openai",
        },
      },
    },
  },
  mistral_ollama = {
    ["llm/v1/chat"] = {
      config = {
        name = "mistral-tiny",
        provider = "mistral",
        options = {
          max_tokens = 512,
          temperature = 0.5,
          mistral_format = "ollama",
        },
      },
    },
  },
  gemini = {
    ["llm/v1/chat"] = {
      config = {
        name = "gemini-pro",
        provider = "gemini",
        options = {
          max_tokens = 8192,
          temperature = 0.8,
          top_k = 1,
          top_p = 0.6,
        },
      },
    },
  },
  bedrock = {
    ["llm/v1/chat"] = {
      config = {
        name = "bedrock",
        provider = "bedrock",
        options = {
          max_tokens = 8192,
          temperature = 0.8,
          top_k = 1,
          top_p = 0.6,
        },
      },
    },
  },
}

local STREAMS = {
  openai = {
    ["llm/v1/chat"] = {
      name = "gpt-4",
      provider = "openai",
    },
    ["llm/v1/completions"] = {
      name = "gpt-3.5-turbo-instruct",
      provider = "openai",
    },
  },
  cohere = {
    ["llm/v1/chat"] = {
      name = "command",
      provider = "cohere",
    },
    ["llm/v1/completions"] = {
      name = "command-light",
      provider = "cohere",
    },
  },
}

local expected_stream_choices = {
  ["llm/v1/chat"] = {
    [1] = {
      delta = {
        content = "the answer",
      },
      finish_reason = ngx.null,
      index = 0,
      logprobs = ngx.null,
    },
  },
  ["llm/v1/completions"] = {
    [1] = {
      text = "the answer",
      finish_reason = ngx.null,
      index = 0,
      logprobs = ngx.null,
    },
  },
}

describe(PLUGIN_NAME .. ": (unit)", function()
  setup(function()
    package.loaded["kong.llm.drivers.shared"] = nil
    _G.TEST = true
    ai_shared = require("kong.llm.drivers.shared")
  end)

  teardown(function()
    _G.TEST = nil
  end)

  it("resolves referenceable plugin configuration from request context", function()
    local fake_request = {
      ["get_header"] = function(header_name)
        local headers = {
          ["from_header_1"] = "header_value_here_1",
          ["from_header_2"] = "header_value_here_2",
        }
        return headers[header_name]
      end,

      ["get_uri_captures"] = function()
        return {
          ["named"] = {
            ["uri_cap_1"] = "cap_value_here_1",
            ["uri_cap_2"] = "cap_value_here_2",
          },
        }
      end,

      ["get_query_arg"] = function(query_arg_name)
        local query_args = {
          ["arg_1"] = "arg_value_here_1",
          ["arg_2"] = "arg_value_here_2",
        }
        return query_args[query_arg_name]
      end,
    }

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "$(headers.from_header_1)",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures.uri_cap_1)",
          azure_deployment_id = "$(headers.from_header_1)",
          azure_api_version = "$(query_params.arg_1)",
          upstream_url = "https://$(uri_captures.uri_cap_1).example.com",
          bedrock = {
            aws_region = "$(uri_captures.uri_cap_1)",
          }
        },
      },
    }

    local result, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.is_falsy(err)
    assert.same(result.model.name, "header_value_here_1")
    assert.same(result.model.options, {
      azure_api_version = 'arg_value_here_1',
      azure_deployment_id = 'header_value_here_1',
      azure_instance = 'cap_value_here_1',
      max_tokens = 256,
      temperature = 1,
      upstream_url = "https://cap_value_here_1.example.com",
      bedrock = {
        aws_region = "cap_value_here_1",
      },
    })
  end)

  it("returns appropriate error when referenceable plugin configuration is missing from request context", function()
    local fake_request = {
      ["get_header"] = function(header_name)
        local headers = {
          ["from_header_1"] = "header_value_here_1",
          ["from_header_2"] = "header_value_here_2",
        }
        return headers[header_name]
      end,

      ["get_uri_captures"] = function()
        return {
          ["named"] = {
            ["uri_cap_1"] = "cap_value_here_1",
            ["uri_cap_2"] = "cap_value_here_2",
          },
        }
      end,

      ["get_query_arg"] = function(query_arg_name)
        local query_args = {
          ["arg_1"] = "arg_value_here_1",
          ["arg_2"] = "arg_value_here_2",
        }
        return query_args[query_arg_name]
      end,
    }

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "gpt-3.5-turbo",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures.uri_cap_3)",
          azure_deployment_id = "$(headers.from_header_1)",
          azure_api_version = "$(query_params.arg_1)",
        },
      },
    }

    local _, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.same("uri_captures key uri_cap_3 was not provided", err)

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "gpt-3.5-turbo",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures.uri_cap_1)",
          azure_deployment_id = "$(headers.from_header_1)",
          azure_api_version = "$(query_params.arg_1)",
          bedrock = {
            aws_region = "$(uri_captures.uri_cap_3)",
          }
        },
      },
    }

    local _, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.same("uri_captures key uri_cap_3 was not provided", err)

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "gpt-3.5-turbo",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures_uri_cap_1)",
        },
      },
    }

    local _, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.same("cannot parse expression for field '$(uri_captures_uri_cap_1)'", err)
  end)

  it("llm/v1/chat message is compatible with llm/v1/chat route", function()
    local compatible, err = llm.is_compatible(SAMPLE_LLM_V1_CHAT, "llm/v1/chat")

    assert.is_truthy(compatible)
    assert.is_nil(err)
  end)

  it("llm/v1/chat message is not compatible with llm/v1/completions route", function()
    local compatible, err = llm.is_compatible(SAMPLE_LLM_V1_CHAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("[llm/v1/chat] message format is not compatible with [llm/v1/completions] route type", err)
  end)

  it("double-format message is denied", function()
    local compatible, err = llm.is_compatible(SAMPLE_DOUBLE_FORMAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("request matches multiple LLM request formats", err)
  end)

  it("double-format message is denied", function()
    local compatible, err = llm.is_compatible(SAMPLE_DOUBLE_FORMAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("request matches multiple LLM request formats", err)
  end)

  for i, j in pairs(FORMATS) do

    describe(i .. " format tests", function()

      for k, l in pairs(j) do

        ---- actual testing code begins here
        describe(k .. " format test", function()

          local actual_request_table
          local driver = require("kong.llm.drivers." .. l.config.provider)


          -- what we do is first put the SAME request message from the user, through the converter, for this provider/format
          it("converts to provider request format correctly", function()
            -- load and check the driver
            assert(driver)

            -- load the standardised request, for this object type
            local request_json = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/requests/%s.json", pl_replace(k, "/", "-")))
            local request_table, err = cjson.decode(request_json)
            assert.is_nil(err)

            -- send it
            local content_type, err
            actual_request_table, content_type, err = driver.to_format(request_table, l.config, k)
            assert.is_nil(err)
            assert.not_nil(content_type)

            -- load the expected outbound request to this provider
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end

            local expected_request_json = pl_file.read(filename)
            local expected_request_table, err = cjson.decode(expected_request_json)
            assert.is_nil(err)

            -- compare the tables
            assert.same(expected_request_table, actual_request_table)
          end)


          -- then we put it through the converter that should come BACK from the provider, towards the user
          it("converts from provider response format correctly", function()
            -- load and check the driver
            assert(driver)

            -- load what the endpoint would really response with
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end
            local virtual_response_json = pl_file.read(filename)

            -- convert to kong format (emulate on response phase hook)
            local actual_response_json, err = driver.from_format(virtual_response_json, l.config, k)
            assert.is_nil(err)

            local actual_response_table, err = cjson.decode(actual_response_json)
            assert.is_nil(err)

            -- load the expected response body
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end
            local expected_response_json = pl_file.read(filename)
            local expected_response_table, err = cjson.decode(expected_response_json)
            assert.is_nil(err)

            -- compare the tables
            assert.same(expected_response_table.choices[1].message, actual_response_table.choices[1].message)
            assert.same(actual_response_table.model, expected_response_table.model)
          end)
        end)
      end
    end)
  end

  -- streaming tests
  for provider_name, provider_format in pairs(STREAMS) do

    describe(provider_name .. " stream format tests", function()

      for format_name, config in pairs(provider_format) do

        ---- actual testing code begins here
        describe(format_name .. " format test", function()
          local driver = require("kong.llm.drivers." .. config.provider)

          -- what we do is first put the SAME request message from the user, through the converter, for this provider/format
          it("converts to provider request format correctly", function()
            -- load the real provider frame from file
            local real_stream_frame = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/real-stream-frames/%s/%s.txt", config.provider, pl_replace(format_name, "/", "-")))

            -- use the shared function to produce an SSE format object
            local real_transformed_frame, err = ai_shared._frame_to_events(real_stream_frame)
            assert.is_nil(err)

            -- transform the SSE frame into OpenAI format
            real_transformed_frame, err = driver.from_format(real_transformed_frame[1], config, "stream/" .. format_name)
            assert.is_nil(err)
            real_transformed_frame, err = cjson.decode(real_transformed_frame)
            assert.is_nil(err)

            -- check it's what we expeced
            assert.same(expected_stream_choices[format_name], real_transformed_frame.choices)
          end)

        end)
      end
    end)

  end

  -- generic tests
  it("throws correct error when format is not supported", function()
    local driver = require("kong.llm.drivers.mistral")  -- one-shot, random example of provider with only prompt support

    local model_config = {
      route_type = "llm/v1/chatnopenotsupported",
      name = "mistral-tiny",
      provider = "mistral",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        mistral_format = "ollama",
      },
    }

    local request_json = pl_file.read("spec/fixtures/ai-proxy/unit/requests/llm-v1-chat.json")
    local request_table, err = cjson.decode(request_json)
    assert.is_falsy(err)

    -- send it
    local actual_request_table, content_type, err = driver.to_format(request_table, model_config, model_config.route_type)
    assert.is_nil(actual_request_table)
    assert.is_nil(content_type)
    assert.equal(err, "no transformer available to format mistral://llm/v1/chatnopenotsupported/ollama")
  end)


  it("produces a correct default config merge", function()
    local formatted, err = ai_shared.merge_config_defaults(
      SAMPLE_LLM_V1_CHAT_WITH_SOME_OPTS,
      {
        max_tokens = 1024,
        top_p = 0.5,
      },
      "llm/v1/chat"
    )

    formatted.messages = nil  -- not needed for config merge

    assert.is_nil(err)
    assert.same({
      max_tokens          = 1024,
      temperature         = 0.1,
      top_p               = 0.5,
      some_extra_param    = "string_val",
      another_extra_param = 0.5,
    }, formatted)
  end)

  describe("streaming transformer tests", function()
    before_each(function()
      ai_shared._set_kong({
        ctx = {
          plugin = {}
        },
        log = {
          debug = function(...)
            print("[DEBUG] ", ...)
          end,
          err = function(...)
            print("[ERROR] ", ...)
          end,
        },
      })
    end)

    after_each(function()
      ai_shared._set_kong(nil)
    end)

    it("transforms Gemini type (split into two parts)", function()
      -- result
      local expected_result = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/expected-output.bin"))

      -- body_filter 1
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/input-1.bin"))
      local events_1 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 2
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/input-2.bin"))
      local events_2 = ai_shared._frame_to_events(input, "application/json")

      -- combine the two
      local result = ""
      for _, event_1 in ipairs(events_1) do
        result = result .. cjson.decode(event_1.data).candidates[1].content.parts[1].text
      end
      for _, event_2 in ipairs(events_2) do
        result = result .. cjson.decode(event_2.data).candidates[1].content.parts[1].text
      end

      assert.same(expected_result, result, true)
    end)

    it("transforms Gemini type (split into three parts)", function()
      -- result
      local expected_result = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/expected-output.bin"))

      -- body_filter 1
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-1.bin"))
      local events_1 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 2
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-2.bin"))
      local events_2 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 3
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-3.bin"))
      local events_3 = ai_shared._frame_to_events(input, "application/json")

      -- combine the two
      local result = ""
      for _, event_1 in ipairs(events_1) do
        result = result .. cjson.decode(event_1.data).candidates[1].content.parts[1].text
      end
      for _, event_2 in ipairs(events_2) do
        result = result .. cjson.decode(event_2.data).candidates[1].content.parts[1].text
      end
      for _, event_3 in ipairs(events_3) do
        result = result .. cjson.decode(event_3.data).candidates[1].content.parts[1].text
      end

      assert.same(expected_result, result, true)
    end)

    it("transforms Gemini type (beginning of stream)", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/json")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events, true)
    end)

    it("transforms Gemini type (end of stream)", function()
      kong.ctx.plugin.gemini_state = {
        started = true,
        eof = false,
        input = "",
        pos = 1,
      }
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/json")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events, true)
    end)

    it("transforms complete-json type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/input.bin"))
      local events = ai_shared._frame_to_events(input, "text/event-stream")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events)
    end)

    it("transforms text/event-stream type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/input.bin"))
      local events = ai_shared._frame_to_events(input, "text/event-stream")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events)
    end)

    it("transforms application/vnd.amazon.eventstream (AWS) type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/aws/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/vnd.amazon.eventstream")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/aws/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.equal(#events, #expected_events)
      for i, _ in ipairs(expected_events) do
        -- tables are random ordered, so we need to compare each serialized event
        assert.same(cjson.decode(events[i].data), cjson.decode(expected_events[i].data))
      end
    end)

  end)

  describe("count_words", function()
    local c = ai_shared._count_words

    it("normal prompts", function()
      assert.same(10, c(string.rep("apple ", 10)))
    end)

    it("multi-modal prompts", function()
      assert.same(10, c({
        {
          type = "text",
          text = string.rep("apple ", 10),
        },
      }))

      assert.same(20, c({
        {
          type = "text",
          text = string.rep("apple ", 10),
        },
        {
          type = "text",
          text = string.rep("banana ", 10),
        },
      }))

      assert.same(10, c({
        {
          type = "not_text",
          text = string.rep("apple ", 10),
        },
        {
          type = "text",
          text = string.rep("banana ", 10),
        },
        {
          type = "text",
          -- somehow malformed
        },
      }))
    end)
  end)

  describe("gemini multimodal", function()
    local gemini_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.gemini"] = nil
      gemini_driver = require("kong.llm.drivers.gemini")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms a text type prompt to gemini GOOD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "text",
          ["text"] = "What is in this picture?",
        })

      assert.not_nil(gemini_prompt)
      assert.is_nil(err)

      assert.same(gemini_prompt,
        {
          ["text"] = "What is in this picture?",
        })
    end)

    it("transforms a text type prompt to gemini BAD MISSING TEXT FIELD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "text",
          ["bad_text_field"] = "What is in this picture?",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("message part type is 'text' but is missing .text block", err)
    end)

    it("transforms an image_url type prompt when data is a URL to gemini GOOD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "image_url",
          ["image_url"] = {
            ["url"] = "https://example.local/image.jpg",
          },
        })

      assert.not_nil(gemini_prompt)
      assert.is_nil(err)

      assert.same(gemini_prompt,
        {
          ["fileData"] = {
            ["fileUri"] = "https://example.local/image.jpg",
            ["mimeType"] = "image/generic",
          },
        })
    end)

    it("transforms an image_url type prompt when data is a URL to gemini BAD MISSING IMAGE FIELD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "image_url",
          ["image_url"] = "https://example.local/image.jpg",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("message part type is 'image_url' but is missing .image_url.url block", err)
    end)

    it("fails to transform a non-mapped multimodal entity type", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "doesnt_exist",
          ["doesnt_exist"] = "https://example.local/video.mp4",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("cannot transform part of type 'doesnt_exist' to Gemini format", err)
    end)

    it("transforms 'describe this image' via URL from openai to gemini", function()
      local gemini_prompt, _, err = gemini_driver._to_gemini_chat_openai(SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_URL)

      assert.is_nil(err)
      assert.not_nil(gemini_prompt)

      gemini_prompt.generationConfig = nil  -- not needed for comparison

      assert.same({
        ["contents"] = {
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "What is in this picture?",
              },
              {
                ["fileData"] = {
                  ["fileUri"] = "https://example.local/image.jpg",
                  ["mimeType"] = "image/generic",
                },
              }
            },
          },
          {
            ["role"] = "model",
            ["parts"] = {
              {
                ["text"] = "A picture of a cat.",
              },
            },
          },
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "Now draw it wearing a party-hat.",
              },
            },
          },
        }
      }, gemini_prompt)
    end)

    it("transforms 'describe this image' via base64 from openai to gemini", function()
      local gemini_prompt, _, err = gemini_driver._to_gemini_chat_openai(SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_B64)

      assert.is_nil(err)
      assert.not_nil(gemini_prompt)

      gemini_prompt.generationConfig = nil  -- not needed for comparison

      assert.same({
        ["contents"] = {
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "What is in this picture?",
              },
              {
                ["inlineData"] = {
                  ["data"] = "Y2F0X3BuZ19oZXJlX2xvbAo=",
                  ["mimeType"] = "image/png",
                },
              }
            },
          },
          {
            ["role"] = "model",
            ["parts"] = {
              {
                ["text"] = "A picture of a cat.",
              },
            },
          },
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "Now draw it wearing a party-hat.",
              },
            },
          },
        }
      }, gemini_prompt)
    end)

  end)


  describe("gemini tools", function()
    local gemini_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.gemini"] = nil
      gemini_driver = require("kong.llm.drivers.gemini")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms openai tools to gemini tools GOOD", function()
      local gemini_tools = gemini_driver._to_tools(SAMPLE_OPENAI_TOOLS_REQUEST.tools)

      assert.not_nil(gemini_tools)
      assert.same(gemini_tools, {
        {
          function_declarations = {
            {
              description = "Check a product is in stock.",
              name = "check_stock",
              parameters = {
                properties = {
                  product_name = {
                    type = "string"
                  }
                },
                required = {
                  "product_name"
                },
                type = "object"
              }
            }
          }
        }
      })
    end)

    it("transforms openai tools to gemini tools NO_TOOLS", function()
      local gemini_tools = gemini_driver._to_tools(SAMPLE_LLM_V1_CHAT)

      assert.is_nil(gemini_tools)
    end)

    it("transforms openai tools to gemini tools NIL", function()
      local gemini_tools = gemini_driver._to_tools(nil)

      assert.is_nil(gemini_tools)
    end)

    it("transforms gemini tools to openai tools GOOD", function()
      local openai_tools = gemini_driver._from_gemini_chat_openai(SAMPLE_GEMINI_TOOLS_RESPONSE, {}, "llm/v1/chat")

      assert.not_nil(openai_tools)

      openai_tools = cjson.decode(openai_tools)
      assert.same(openai_tools.choices[1].message.tool_calls[1]['function'], {
        name = "sql_execute",
        arguments = "{\"product_name\":\"NewPhone\"}"
      })
    end)
  end)

  describe("bedrock tools", function()
    local bedrock_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.bedrock"] = nil
      bedrock_driver = require("kong.llm.drivers.bedrock")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms openai tools to bedrock tools GOOD", function()
      local bedrock_tools = bedrock_driver._to_tools(SAMPLE_OPENAI_TOOLS_REQUEST.tools)

      assert.not_nil(bedrock_tools)
      assert.same(bedrock_tools, {
        {
          toolSpec = {
            description = "Check a product is in stock.",
            inputSchema = {
              json = {
                properties = {
                  product_name = {
                    type = "string"
                  }
                },
                required = {
                  "product_name"
                },
                type = "object"
              }
            },
            name = "check_stock"
          }
        }
      })
    end)

    it("transforms openai tools to bedrock tools NO_TOOLS", function()
      local bedrock_tools = bedrock_driver._to_tools(SAMPLE_LLM_V1_CHAT)

      assert.is_nil(bedrock_tools)
    end)

    it("transforms openai tools to bedrock tools NIL", function()
      local bedrock_tools = bedrock_driver._to_tools(nil)

      assert.is_nil(bedrock_tools)
    end)

    it("transforms bedrock tools to openai tools GOOD", function()
      local openai_tools = bedrock_driver._from_tool_call_response(SAMPLE_BEDROCK_TOOLS_RESPONSE.output.message.content)

      assert.not_nil(openai_tools)

      assert.same(openai_tools[1]['function'], {
        name = "sumArea",
        arguments = "{\"areas\":[121,212,313]}"
      })
    end)

    it("transforms guardrails into bedrock generation config", function()
      local model_info = {
        route_type = "llm/v1/chat",
        name = "some-model",
        provider = "bedrock",
      }
      local bedrock_guardrails = bedrock_driver._to_bedrock_chat_openai(SAMPLE_LLM_V1_CHAT_WITH_GUARDRAILS, model_info, "llm/v1/chat")

      assert.not_nil(bedrock_guardrails)

      assert.same(bedrock_guardrails.guardrailConfig, {
        ['guardrailIdentifier'] = 'yu5xwvfp4sud',
        ['guardrailVersion'] = '1',
        ['trace'] = 'enabled',
      })
    end)
  end)
end)


describe(PLUGIN_NAME .. ": (unit)", function()
  setup(function()
    package.loaded["kong.llm.drivers.shared"] = nil
    _G.TEST = true
    ai_shared = require("kong.llm.drivers.shared")
  end)

  teardown(function()
    _G.TEST = nil
  end)

  it("resolves referenceable plugin configuration from request context", function()
    local fake_request = {
      ["get_header"] = function(header_name)
        local headers = {
          ["from_header_1"] = "header_value_here_1",
          ["from_header_2"] = "header_value_here_2",
        }
        return headers[header_name]
      end,

      ["get_uri_captures"] = function()
        return {
          ["named"] = {
            ["uri_cap_1"] = "cap_value_here_1",
            ["uri_cap_2"] = "cap_value_here_2",
          },
        }
      end,

      ["get_query_arg"] = function(query_arg_name)
        local query_args = {
          ["arg_1"] = "arg_value_here_1",
          ["arg_2"] = "arg_value_here_2",
        }
        return query_args[query_arg_name]
      end,
    }

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "gpt-3.5-turbo",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures.uri_cap_1)",
          azure_deployment_id = "$(headers.from_header_1)",
          azure_api_version = "$(query_params.arg_1)",
        },
      },
    }

    local result, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.is_falsy(err)
    assert.same(result.model.options, {
      ['azure_api_version'] = 'arg_value_here_1',
      ['azure_deployment_id'] = 'header_value_here_1',
      ['azure_instance'] = 'cap_value_here_1',
      ['max_tokens'] = 256,
      ['temperature'] = 1,
    })
  end)

  it("resolves referenceable model name from request context", function()
    local fake_request = {
      ["get_header"] = function(header_name)
        local headers = {
          ["from_header_1"] = "header_value_here_1",
          ["from_header_2"] = "header_value_here_2",
        }
        return headers[header_name]
      end,

      ["get_uri_captures"] = function()
        return {
          ["named"] = {
            ["uri_cap_1"] = "cap_value_here_1",
            ["uri_cap_2"] = "cap_value_here_2",
          },
        }
      end,

      ["get_query_arg"] = function(query_arg_name)
        local query_args = {
          ["arg_1"] = "arg_value_here_1",
          ["arg_2"] = "arg_value_here_2",
        }
        return query_args[query_arg_name]
      end,
    }

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "$(uri_captures.uri_cap_2)",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "string-1",
          azure_deployment_id = "string-2",
          azure_api_version = "string-3",
        },
      },
    }

    local result, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.is_falsy(err)
    assert.same("cap_value_here_2", result.model.name)
  end)

  it("returns appropriate error when referenceable plugin configuration is missing from request context", function()
    local fake_request = {
      ["get_header"] = function(header_name)
        local headers = {
          ["from_header_1"] = "header_value_here_1",
          ["from_header_2"] = "header_value_here_2",
        }
        return headers[header_name]
      end,

      ["get_uri_captures"] = function()
        return {
          ["named"] = {
            ["uri_cap_1"] = "cap_value_here_1",
            ["uri_cap_2"] = "cap_value_here_2",
          },
        }
      end,

      ["get_query_arg"] = function(query_arg_name)
        local query_args = {
          ["arg_1"] = "arg_value_here_1",
          ["arg_2"] = "arg_value_here_2",
        }
        return query_args[query_arg_name]
      end,
    }

    local fake_config = {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "api-key",
        header_value = "azure-key",
      },
      model = {
        name = "gpt-3.5-turbo",
        provider = "azure",
        options = {
          max_tokens = 256,
          temperature = 1.0,
          azure_instance = "$(uri_captures.uri_cap_3)",
          azure_deployment_id = "$(headers.from_header_1)",
          azure_api_version = "$(query_params.arg_1)",
        },
      },
    }

    local _, err = ai_shared.merge_model_options(fake_request, fake_config)
    assert.same("uri_captures key uri_cap_3 was not provided", err)
  end)

  it("llm/v1/chat message is compatible with llm/v1/chat route", function()
    local compatible, err = llm.is_compatible(SAMPLE_LLM_V1_CHAT, "llm/v1/chat")

    assert.is_truthy(compatible)
    assert.is_nil(err)
  end)

  it("llm/v1/chat message is not compatible with llm/v1/completions route", function()
    local compatible, err = llm.is_compatible(SAMPLE_LLM_V1_CHAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("[llm/v1/chat] message format is not compatible with [llm/v1/completions] route type", err)
  end)

  it("double-format message is denied", function()
    local compatible, err = llm.is_compatible(SAMPLE_DOUBLE_FORMAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("request matches multiple LLM request formats", err)
  end)

  it("double-format message is denied", function()
    local compatible, err = llm.is_compatible(SAMPLE_DOUBLE_FORMAT, "llm/v1/completions")

    assert.is_falsy(compatible)
    assert.same("request matches multiple LLM request formats", err)
  end)

  for i, j in pairs(FORMATS) do

    describe(i .. " format tests", function()

      for k, l in pairs(j) do

        ---- actual testing code begins here
        describe(k .. " format test", function()

          local actual_request_table
          local driver = require("kong.llm.drivers." .. l.config.provider)


          -- what we do is first put the SAME request message from the user, through the converter, for this provider/format
          it("converts to provider request format correctly", function()
            -- load and check the driver
            assert(driver)

            -- load the standardised request, for this object type
            local request_json = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/requests/%s.json", pl_replace(k, "/", "-")))
            local request_table, err = cjson.decode(request_json)
            assert.is_nil(err)

            -- send it
            local content_type, err
            actual_request_table, content_type, err = driver.to_format(request_table, l.config, k)
            assert.is_nil(err)
            assert.not_nil(content_type)

            -- load the expected outbound request to this provider
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end

            local expected_request_json = pl_file.read(filename)
            local expected_request_table, err = cjson.decode(expected_request_json)
            assert.is_nil(err)

            -- compare the tables
            assert.same(expected_request_table, actual_request_table)
          end)


          -- then we put it through the converter that should come BACK from the provider, towards the user
          it("converts from provider response format correctly", function()
            -- load and check the driver
            assert(driver)

            -- load what the endpoint would really response with
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end
            local virtual_response_json = pl_file.read(filename)

            -- convert to kong format (emulate on response phase hook)
            local actual_response_json, err = driver.from_format(virtual_response_json, l.config, k)
            assert.is_nil(err)

            local actual_response_table, err = cjson.decode(actual_response_json)
            assert.is_nil(err)

            -- load the expected response body
            local filename
            if l.config.provider == "llama2" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s/%s.json", l.config.provider, l.config.options.llama2_format, pl_replace(k, "/", "-"))

            elseif l.config.provider == "mistral" then
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s/%s.json", l.config.provider, l.config.options.mistral_format, pl_replace(k, "/", "-"))

            else
              filename = fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s.json", l.config.provider, pl_replace(k, "/", "-"))

            end
            local expected_response_json = pl_file.read(filename)
            local expected_response_table, err = cjson.decode(expected_response_json)
            assert.is_nil(err)

            -- compare the tables
            assert.same(expected_response_table.choices[1].message, actual_response_table.choices[1].message)
            assert.same(actual_response_table.model, expected_response_table.model)
          end)
        end)
      end
    end)
  end

  -- streaming tests
  for provider_name, provider_format in pairs(STREAMS) do

    describe(provider_name .. " stream format tests", function()

      for format_name, config in pairs(provider_format) do

        ---- actual testing code begins here
        describe(format_name .. " format test", function()
          local driver = require("kong.llm.drivers." .. config.provider)

          -- what we do is first put the SAME request message from the user, through the converter, for this provider/format
          it("converts to provider request format correctly", function()
            -- load the real provider frame from file
            local real_stream_frame = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/real-stream-frames/%s/%s.txt", config.provider, pl_replace(format_name, "/", "-")))

            -- use the shared function to produce an SSE format object
            local real_transformed_frame, err = ai_shared._frame_to_events(real_stream_frame)
            assert.is_nil(err)

            -- transform the SSE frame into OpenAI format
            real_transformed_frame, err = driver.from_format(real_transformed_frame[1], config, "stream/" .. format_name)
            assert.is_nil(err)
            real_transformed_frame, err = cjson.decode(real_transformed_frame)
            assert.is_nil(err)

            -- check it's what we expeced
            assert.same(expected_stream_choices[format_name], real_transformed_frame.choices)
          end)

        end)
      end
    end)

  end

  -- generic tests
  it("throws correct error when format is not supported", function()
    local driver = require("kong.llm.drivers.mistral")  -- one-shot, random example of provider with only prompt support

    local model_config = {
      route_type = "llm/v1/chatnopenotsupported",
      name = "mistral-tiny",
      provider = "mistral",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        mistral_format = "ollama",
      },
    }

    local request_json = pl_file.read("spec/fixtures/ai-proxy/unit/requests/llm-v1-chat.json")
    local request_table, err = cjson.decode(request_json)
    assert.is_falsy(err)

    -- send it
    local actual_request_table, content_type, err = driver.to_format(request_table, model_config, model_config.route_type)
    assert.is_nil(actual_request_table)
    assert.is_nil(content_type)
    assert.equal(err, "no transformer available to format mistral://llm/v1/chatnopenotsupported/ollama")
  end)


  it("produces a correct default config merge", function()
    local formatted, err = ai_shared.merge_config_defaults(
      SAMPLE_LLM_V1_CHAT_WITH_SOME_OPTS,
      {
        max_tokens = 1024,
        top_p = 0.5,
      },
      "llm/v1/chat"
    )

    formatted.messages = nil  -- not needed for config merge

    assert.is_nil(err)
    assert.same({
      max_tokens          = 1024,
      temperature         = 0.1,
      top_p               = 0.5,
      some_extra_param    = "string_val",
      another_extra_param = 0.5,
    }, formatted)
  end)

  describe("streaming transformer tests", function()
    before_each(function()
      ai_shared._set_kong({
        ctx = {
          plugin = {}
        },
        log = {
          debug = function(...)
            print("[DEBUG] ", ...)
          end,
          err = function(...)
            print("[ERROR] ", ...)
          end,
        },
      })
    end)

    after_each(function()
      ai_shared._set_kong(nil)
    end)

    it("transforms Gemini type (split into two parts)", function()
      -- result
      local expected_result = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/expected-output.bin"))

      -- body_filter 1
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/input-1.bin"))
      local events_1 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 2
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split/input-2.bin"))
      local events_2 = ai_shared._frame_to_events(input, "application/json")

      -- combine the two
      local result = ""
      for _, event_1 in ipairs(events_1) do
        result = result .. cjson.decode(event_1.data).candidates[1].content.parts[1].text
      end
      for _, event_2 in ipairs(events_2) do
        result = result .. cjson.decode(event_2.data).candidates[1].content.parts[1].text
      end

      assert.same(expected_result, result, true)
    end)

    it("transforms Gemini type (split into three parts)", function()
      -- result
      local expected_result = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/expected-output.bin"))

      -- body_filter 1
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-1.bin"))
      local events_1 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 2
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-2.bin"))
      local events_2 = ai_shared._frame_to_events(input, "application/json")

      -- body_filter 3
      input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-split-three-parts/input-3.bin"))
      local events_3 = ai_shared._frame_to_events(input, "application/json")

      -- combine the two
      local result = ""
      for _, event_1 in ipairs(events_1) do
        result = result .. cjson.decode(event_1.data).candidates[1].content.parts[1].text
      end
      for _, event_2 in ipairs(events_2) do
        result = result .. cjson.decode(event_2.data).candidates[1].content.parts[1].text
      end
      for _, event_3 in ipairs(events_3) do
        result = result .. cjson.decode(event_3.data).candidates[1].content.parts[1].text
      end

      assert.same(expected_result, result, true)
    end)

    it("transforms Gemini type (beginning of stream)", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/json")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events, true)
    end)

    it("transforms Gemini type (end of stream)", function()
      kong.ctx.plugin.gemini_state = {
        started = true,
        eof = false,
        input = "",
        pos = 1,
      }
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/json")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events, true)
    end)

    it("transforms complete-json type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/input.bin"))
      local events = ai_shared._frame_to_events(input, "text/event-stream")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events)
    end)

    it("transforms text/event-stream type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/input.bin"))
      local events = ai_shared._frame_to_events(input, "text/event-stream")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(expected_events, events)

      local len = #input
      -- Fuzz with possible truncations. We choose to truncate into three parts, so we can test
      -- a case that the frame is truncated into more than two parts, to avoid unexpected cleanup
      -- of the truncation state.
      for i = 2, len - 1 do
        for j = i + 1, len do
          local events = {}
          local delimiters = {}
          delimiters[1] = {1, i - 1}
          delimiters[2] = {i, j - 1}
          delimiters[3] = {j, len}
          for k = 1, #delimiters do
            local output = ai_shared._frame_to_events(input:sub(delimiters[k][1], delimiters[k][2]), "text/event-stream")
            for _, event in ipairs(output or {}) do
              table.insert(events, event)
            end
          end
          assert.same(expected_events, events, "failed when the frame is truncated in " .. cjson.encode(delimiters))
        end
      end
    end)

    it("transforms application/vnd.amazon.eventstream (AWS) type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/aws/input.bin"))
      local events = ai_shared._frame_to_events(input, "application/vnd.amazon.eventstream")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/aws/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.equal(#events, #expected_events)
      for i, _ in ipairs(expected_events) do
        -- tables are random ordered, so we need to compare each serialized event
        assert.same(cjson.decode(events[i].data), cjson.decode(expected_events[i].data))
      end

      local len = #input
      -- fuzz with random truncations
      for i = 1, len / 2, 10 do
        local events = {}

        for j = 0, 2 do
          local stop = i * j + i
          if j == 2 then
            -- the last truncated frame
            stop = len
          end
          local output = ai_shared._frame_to_events(input:sub(i * j + 1, stop), "application/vnd.amazon.eventstream")
          for _, event in ipairs(output or {}) do
            table.insert(events, event)
          end
        end
        for i, _ in ipairs(expected_events) do
          assert.same(cjson.decode(events[i].data), cjson.decode(expected_events[i].data), "failed when the frame is truncated at " .. i)
        end
      end
    end)

  end)

  describe("count_words", function()
    local c = ai_shared._count_words

    it("normal prompts", function()
      assert.same(10, c(string.rep("apple ", 10)))
    end)

    it("multi-modal prompts", function()
      assert.same(10, c({
        {
          type = "text",
          text = string.rep("apple ", 10),
        },
      }))

      assert.same(20, c({
        {
          type = "text",
          text = string.rep("apple ", 10),
        },
        {
          type = "text",
          text = string.rep("banana ", 10),
        },
      }))

      assert.same(10, c({
        {
          type = "not_text",
          text = string.rep("apple ", 10),
        },
        {
          type = "text",
          text = string.rep("banana ", 10),
        },
        {
          type = "text",
          -- somehow malformed
        },
      }))
    end)
  end)

  describe("gemini multimodal", function()
    local gemini_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.gemini"] = nil
      gemini_driver = require("kong.llm.drivers.gemini")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms a text type prompt to gemini GOOD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "text",
          ["text"] = "What is in this picture?",
        })

      assert.not_nil(gemini_prompt)
      assert.is_nil(err)

      assert.same(gemini_prompt,
        {
          ["text"] = "What is in this picture?",
        })
    end)

    it("transforms a text type prompt to gemini BAD MISSING TEXT FIELD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "text",
          ["bad_text_field"] = "What is in this picture?",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("message part type is 'text' but is missing .text block", err)
    end)

    it("transforms an image_url type prompt when data is a URL to gemini GOOD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "image_url",
          ["image_url"] = {
            ["url"] = "https://example.local/image.jpg",
          },
        })

      assert.not_nil(gemini_prompt)
      assert.is_nil(err)

      assert.same(gemini_prompt,
        {
          ["fileData"] = {
            ["fileUri"] = "https://example.local/image.jpg",
            ["mimeType"] = "image/generic",
          },
        })
    end)

    it("transforms an image_url type prompt when data is a URL to gemini BAD MISSING IMAGE FIELD", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "image_url",
          ["image_url"] = "https://example.local/image.jpg",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("message part type is 'image_url' but is missing .image_url.url block", err)
    end)

    it("fails to transform a non-mapped multimodal entity type", function()
      local gemini_prompt, err = gemini_driver._openai_part_to_gemini_part(
        {
          ["type"] = "doesnt_exist",
          ["doesnt_exist"] = "https://example.local/video.mp4",
        })

      assert.is_nil(gemini_prompt)
      assert.not_nil(err)

      assert.same("cannot transform part of type 'doesnt_exist' to Gemini format", err)
    end)

    it("transforms 'describe this image' via URL from openai to gemini", function()
      local gemini_prompt, _, err = gemini_driver._to_gemini_chat_openai(SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_URL)

      assert.is_nil(err)
      assert.not_nil(gemini_prompt)

      gemini_prompt.generationConfig = nil  -- not needed for comparison

      assert.same({
        ["contents"] = {
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "What is in this picture?",
              },
              {
                ["fileData"] = {
                  ["fileUri"] = "https://example.local/image.jpg",
                  ["mimeType"] = "image/generic",
                },
              }
            },
          },
          {
            ["role"] = "model",
            ["parts"] = {
              {
                ["text"] = "A picture of a cat.",
              },
            },
          },
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "Now draw it wearing a party-hat.",
              },
            },
          },
        }
      }, gemini_prompt)
    end)

    it("transforms 'describe this image' via base64 from openai to gemini", function()
      local gemini_prompt, _, err = gemini_driver._to_gemini_chat_openai(SAMPLE_LLM_V2_CHAT_MULTIMODAL_IMAGE_B64)

      assert.is_nil(err)
      assert.not_nil(gemini_prompt)

      gemini_prompt.generationConfig = nil  -- not needed for comparison

      assert.same({
        ["contents"] = {
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "What is in this picture?",
              },
              {
                ["inlineData"] = {
                  ["data"] = "Y2F0X3BuZ19oZXJlX2xvbAo=",
                  ["mimeType"] = "image/png",
                },
              }
            },
          },
          {
            ["role"] = "model",
            ["parts"] = {
              {
                ["text"] = "A picture of a cat.",
              },
            },
          },
          {
            ["role"] = "user",
            ["parts"] = {
              {
                ["text"] = "Now draw it wearing a party-hat.",
              },
            },
          },
        }
      }, gemini_prompt)
    end)

  end)


  describe("gemini tools", function()
    local gemini_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.gemini"] = nil
      gemini_driver = require("kong.llm.drivers.gemini")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms openai tools to gemini tools GOOD", function()
      local gemini_tools = gemini_driver._to_tools(SAMPLE_OPENAI_TOOLS_REQUEST.tools)

      assert.not_nil(gemini_tools)
      assert.same(gemini_tools, {
        {
          function_declarations = {
            {
              description = "Check a product is in stock.",
              name = "check_stock",
              parameters = {
                properties = {
                  product_name = {
                    type = "string"
                  }
                },
                required = {
                  "product_name"
                },
                type = "object"
              }
            }
          }
        }
      })
    end)

    it("transforms openai tools to gemini tools NO_TOOLS", function()
      local gemini_tools = gemini_driver._to_tools(SAMPLE_LLM_V1_CHAT)

      assert.is_nil(gemini_tools)
    end)

    it("transforms openai tools to gemini tools NIL", function()
      local gemini_tools = gemini_driver._to_tools(nil)

      assert.is_nil(gemini_tools)
    end)

    it("transforms gemini tools to openai tools GOOD", function()
      local openai_tools = gemini_driver._from_gemini_chat_openai(SAMPLE_GEMINI_TOOLS_RESPONSE, {}, "llm/v1/chat")

      assert.not_nil(openai_tools)

      openai_tools = cjson.decode(openai_tools)
      assert.same(openai_tools.choices[1].message.tool_calls[1]['function'], {
        name = "sql_execute",
        arguments = "{\"product_name\":\"NewPhone\"}"
      })
    end)
  end)

  describe("bedrock tools", function()
    local bedrock_driver

    setup(function()
      _G._TEST = true
      package.loaded["kong.llm.drivers.bedrock"] = nil
      bedrock_driver = require("kong.llm.drivers.bedrock")
    end)

    teardown(function()
      _G._TEST = nil
    end)

    it("transforms openai tools to bedrock tools GOOD", function()
      local bedrock_tools = bedrock_driver._to_tools(SAMPLE_OPENAI_TOOLS_REQUEST.tools)

      assert.not_nil(bedrock_tools)
      assert.same(bedrock_tools, {
        {
          toolSpec = {
            description = "Check a product is in stock.",
            inputSchema = {
              json = {
                properties = {
                  product_name = {
                    type = "string"
                  }
                },
                required = {
                  "product_name"
                },
                type = "object"
              }
            },
            name = "check_stock"
          }
        }
      })
    end)

    it("transforms openai tools to bedrock tools NO_TOOLS", function()
      local bedrock_tools = bedrock_driver._to_tools(SAMPLE_LLM_V1_CHAT)

      assert.is_nil(bedrock_tools)
    end)

    it("transforms openai tools to bedrock tools NIL", function()
      local bedrock_tools = bedrock_driver._to_tools(nil)

      assert.is_nil(bedrock_tools)
    end)

    it("transforms bedrock tools to openai tools GOOD", function()
      local openai_tools = bedrock_driver._from_tool_call_response(SAMPLE_BEDROCK_TOOLS_RESPONSE.output.message.content)

      assert.not_nil(openai_tools)

      assert.same(openai_tools[1]['function'], {
        name = "sumArea",
        arguments = "{\"areas\":[121,212,313]}"
      })
    end)

    it("transforms guardrails into bedrock generation config", function()
      local model_info = {
        route_type = "llm/v1/chat",
        name = "some-model",
        provider = "bedrock",
      }
      local bedrock_guardrails = bedrock_driver._to_bedrock_chat_openai(SAMPLE_LLM_V1_CHAT_WITH_GUARDRAILS, model_info, "llm/v1/chat")

      assert.not_nil(bedrock_guardrails)

      assert.same(bedrock_guardrails.guardrailConfig, {
        ['guardrailIdentifier'] = 'yu5xwvfp4sud',
        ['guardrailVersion'] = '1',
        ['trace'] = 'enabled',
      })
    end)
  end)
end)

describe("json_array_iterator", function()
  local json_array_iterator
  lazy_setup(function()
    _G.TEST = true
    package.loaded["kong.llm.drivers.shared"] = nil
    json_array_iterator = require("kong.llm.drivers.shared")._json_array_iterator
  end)

  -- Helper function to collect all elements from iterator
  local function collect_elements(input)
    local elements = {}
    local iter = json_array_iterator(input)
    local next_element = iter()
    while next_element do
      table.insert(elements, next_element)
      next_element = iter()
    end
    return elements
  end

  it("#qq should handle simple flat arrays", function()
    local input = '[1, 2, 3, 4]'
    local elements = collect_elements(input)
    assert.are.same({"1", "2", "3", "4"}, elements)
  end)

  it("should handle arrays with strings", function()
    local input = '["hello", "world"]'
    local elements = collect_elements(input)
    assert.are.same({'"hello"', '"world"'}, elements)
  end)

  it("should handle nested objects", function()
    local input = '[{"name": "John"}, {"name": "Jane"}]'
    local elements = collect_elements(input)
    assert.are.same(
      '{\"name\": \"John\"}',
      elements[1]
    )
    assert.are.same(
      '{\"name\": \"Jane\"}',
      elements[2]
    )
  end)

  it("should handle nested arrays", function()
    local input = '[[1, 2], [3, 4]]'
    local elements = collect_elements(input)
    assert.are.same({"[1, 2]", "[3, 4]"}, elements)
  end)

  it("should handle whitespace", function()
    local input = '  [  1  ,  2  ]  '
    local elements = collect_elements(input)
    assert.are.same({"1", "2"}, elements)
  end)

  it("should handle empty arrays", function()
    local input = '[]'
    local elements = collect_elements(input)
    assert.are.same({}, elements)
  end)

  it("should handle strings with special characters", function()
    local input = '["{\"special\": \"\\\"quoted\\\"\"}", "[1,2]"]'
    local elements = collect_elements(input)
    assert.are.same(
      {'\"{\"special\": \"\\\"quoted\\\"\"}\"', '"[1,2]"'},
      elements
    )
  end)

  describe("incremental parsing", function()
    it("should handle split within string", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- First chunk (split within string)
      iter = json_array_iterator('["hel', state)
      local element, new_state = iter()
      assert.is_nil(element)  -- Should return nil as string is incomplete
      state = new_state

      -- Second chunk (complete string)
      iter = json_array_iterator('lo"]', state)
      element = iter()
      assert.are.same('"hello"', element)
    end)

    it("should handle split within escaped characters", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split during escape sequence
      iter = json_array_iterator('["he\\', state)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator('\\nllo"]', state)
      element = iter()
      assert.are.same('"he\\\\nllo"', element)
    end)

    it("should handle split between object braces", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split between object definition
      iter = json_array_iterator('[{"name": "Jo', state)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator('hn"}, {"age": 30}]', state)
      element = iter()
      assert.are.same('{"name": "John"}', element)

      element = iter()
      assert.are.same('{"age": 30}', element)
    end)

    it("should handle split between array brackets", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split between nested array
      iter = json_array_iterator('[[1, 2', state)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator('], [3, 4]]', state)
      element = iter()
      assert.are.same('[1, 2]', element)

      element = iter()
      assert.are.same('[3, 4]', element)
    end)

    it("should handle split at comma", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split at comma
      iter = json_array_iterator('[1,', state)
      local element, new_state = iter()
      assert.are.same('1', element)
      state = new_state

      iter = json_array_iterator(' 2]', state)
      element = iter()
      assert.are.same('2', element)
    end)

    it("should not split between literal comma", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split at comma
      iter = json_array_iterator('[{"message":"hello world"}, {"message":"goodbye,', state)
      local element, _ = iter()
      assert.are.same('{"message":"hello world"}',element)
      local element, _ = iter()
      assert.is_nil(element)

      iter = json_array_iterator(' world"}]', state)
      element = iter()
      assert.are.same('{"message":"goodbye, world"}', element)
    end)

    it("should handle split within complex nested structure", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Complex nested structure split
      iter = json_array_iterator('[{"users": [{"id": 1', state)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator(', "name": "John"}]}, {"status": "', state)
      local element, new_state = iter()
      assert.are.same('{"users": [{"id": 1, "name": "John"}]}', element)
      state = new_state

      iter = json_array_iterator('active"}]', state)
      element = iter()
      assert.are.same('{"status": "active"}', element)
    end)
  end)

  it("should error on invalid start", function()
    assert.has_error(function()
      json_array_iterator('{1, 2, 3}')()
    end, "Invalid start: expected '['")
  end)

  it("should handle complex nested structures", function()
    local input = '[{"users": [{"id": 1, "name": "John"}, {"id": 2, "name": "Jane"}]}, {"status": "active"}]'
    local elements = collect_elements(input)
    assert.are.same(
      '{\"users\": [{\"id\": 1, \"name\": \"John\"}, {\"id\": 2, \"name\": \"Jane\"}]}',
      elements[1]
    )
    assert.are.same(
      '{\"status\": \"active\"}',
      elements[2]
    )
  end)

  it("#jsonl should handle complex nested jsonl structures", function()
    local input = '{"users": [{"id": 1, "name": "John"}, {"id": 2, "name": "Jane"}]}\n{"status": "active"}'
    local elements = collect_elements(input, true)
    assert.are.same(
      '{\"users\": [{\"id\": 1, \"name\": \"John\"}, {\"id\": 2, \"name\": \"Jane\"}]}',
      elements[1]
    )
    assert.are.same(
      '{\"status\": \"active\"}',
      elements[2]
    )
  end)

  describe("#jsonl incremental parsing", function()
    it("should handle split between object braces", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split between object definition
      iter = json_array_iterator('{"name": "Jo', state, true)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator('hn"}\n{"age": 30}', state, true)
      element = iter()
      assert.are.same('{"name": "John"}', element)

      element = iter()
      assert.are.same('{"age": 30}', element)
    end)

    it("should handle split between array brackets", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split between nested array
      iter = json_array_iterator('[1, 2', state, true)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator(']\n[3, 4]', state, true)
      element = iter()
      assert.are.same('[1, 2]', element)

      element = iter()
      assert.are.same('[3, 4]', element)
    end)

    it("should not split between literal \n", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Split at comma
      iter = json_array_iterator('{"message":"hello world"}\n{"message":"goodbye\\n', state, true)
      local element, _ = iter()
      assert.are.same('{"message":"hello world"}',element)
      local element, _ = iter()
      assert.is_nil(element)

      iter = json_array_iterator(' world"}', state, true)
      element = iter()
      assert.are.same('{"message":"goodbye\\n world"}', element)
    end)

    it("should handle split within complex nested structure", function()
      local state = {
        started = false,
        pos = 1,
        input = '',
        eof = false,
      }
      local iter

      -- Complex nested structure split
      iter = json_array_iterator('{"users": [{"id": 1', state, true)
      local element, new_state = iter()
      assert.is_nil(element)
      state = new_state

      iter = json_array_iterator(', "name": "John"}]}\n{"status": "', state, true)
      local element, new_state = iter()
      assert.are.same('{"users": [{"id": 1, "name": "John"}]}', element)
      state = new_state

      iter = json_array_iterator('active"}', state, true)
      element = iter()
      assert.are.same('{"status": "active"}', element)
    end)
  end)
end)

describe("upstream_url capture groups", function()
  local mock_request

  lazy_setup(function()
  end)

  before_each(function()
    -- Mock Kong request object for testing capture groups
    mock_request = {
      get_uri_captures = function()
        return {
          named = {
            api = "api",
            chat = "chat",
            completions = "completions"
          },
          unnamed = {
            [0] = "/api/chat",
            [1] = "api",
            [2] = "chat"
          }
        }
      end,
      get_header = function(key)
        if key == "x-test-header" then
          return "test-value"
        end
        return nil
      end,
      get_query_arg = function(key)
        if key == "test_param" then
          return "param-value"
        end
        return nil
      end
    }
  end)

  describe("merge_model_options function", function()
    local shared = require "kong.llm.drivers.shared"

    it("resolves capture group templates in upstream_url", function()
      local conf_m = {
        upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)"
      }

      local result, err = shared.merge_model_options(mock_request, conf_m)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/api/chat", result.upstream_url)
    end)

    it("resolves multiple capture groups in same string", function()
      local conf_m = {
        upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)",
        custom_path = "/$(uri_captures.api)-$(uri_captures.chat)-endpoint"
      }

      local result, err = shared.merge_model_options(mock_request, conf_m)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/api/chat", result.upstream_url)
      assert.equal("/api-chat-endpoint", result.custom_path)
    end)

    it("resolves capture groups in nested tables", function()
      local conf_m = {
        model = {
          options = {
            upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)",
            custom_endpoint = "/$(uri_captures.api)/v1"
          }
        }
      }

      local result, err = shared.merge_model_options(mock_request, conf_m)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/api/chat", result.model.options.upstream_url)
      assert.equal("/api/v1", result.model.options.custom_endpoint)
    end)

  end)

  describe("real route scenario tests", function()
    local shared = require "kong.llm.drivers.shared"

    it("simulates llama2-chat route with capture groups", function()
      -- Simulate the actual route configuration from the user's example
      local targets_config = {
        {
          model = {
            options = {
              upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)",
              llama2_format = "ollama"
            },
            provider = "llama2"
          }
        }
      }

      -- Process the first target's model options
      local result, err = shared.merge_model_options(mock_request, targets_config[1].model.options)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/api/chat", result.upstream_url)
      assert.equal("ollama", result.llama2_format)
    end)

    it("handles route path ~/(?<api>[a-z]+)/(?<chat>[a-z]+)$ correctly", function()
      -- Mock a request that would match the route pattern ~/(?<api>[a-z]+)/(?<chat>[a-z]+)$
      -- For request path "/api/chat"
      local request_with_captures = {
        get_uri_captures = function()
          return {
            named = {
              api = "api",
              chat = "chat"
            },
            unnamed = {
              [0] = "/api/chat",
              [1] = "api",
              [2] = "chat"
            }
          }
        end
      }

      local conf_m = {
        upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)"
      }

      local result, err = shared.merge_model_options(request_with_captures, conf_m)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/api/chat", result.upstream_url)
    end)

    it("handles different capture group values dynamically", function()
      -- Test with different capture values that could match the regex pattern
      local request_with_v1_completions = {
        get_uri_captures = function()
          return {
            named = {
              api = "v1",
              chat = "completions"
            },
            unnamed = {
              [0] = "/v1/completions",
              [1] = "v1",
              [2] = "completions"
            }
          }
        end
      }

      local conf_m = {
        upstream_url = "http://127.0.0.1:11434/$(uri_captures.api)/$(uri_captures.chat)"
      }

      local result, err = shared.merge_model_options(request_with_v1_completions, conf_m)

      assert.is_nil(err)
      assert.not_nil(result)
      assert.equal("http://127.0.0.1:11434/v1/completions", result.upstream_url)
    end)
  end)

end)