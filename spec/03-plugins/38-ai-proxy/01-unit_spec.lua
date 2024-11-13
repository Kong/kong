local PLUGIN_NAME = "ai-proxy"
local pl_file = require("pl.file")
local pl_replace = require("pl.stringx").replace
local cjson = require("cjson.safe")
local fmt = string.format
local llm = require("kong.llm")
local ai_shared = require("kong.llm.drivers.shared")

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

    local result, err = ai_shared.resolve_plugin_conf(fake_request, fake_config)
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

    local result, err = ai_shared.resolve_plugin_conf(fake_request, fake_config)
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

    local _, err = ai_shared.resolve_plugin_conf(fake_request, fake_config)
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
            local real_transformed_frame, err = ai_shared.frame_to_events(real_stream_frame)
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

    it("transforms truncated-json type (beginning of stream)", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/input.bin"))
      local events = ai_shared.frame_to_events(input, "gemini")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-beginning/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(events, expected_events, true)
    end)

    it("transforms truncated-json type (end of stream)", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/input.bin"))
      local events = ai_shared.frame_to_events(input, "gemini")

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/partial-json-end/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(events, expected_events, true)
    end)

    it("transforms complete-json type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/input.bin"))
      local events = ai_shared.frame_to_events(input, "cohere")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/complete-json/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(events, expected_events)
    end)

    it("transforms text/event-stream type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/input.bin"))
      local events = ai_shared.frame_to_events(input, "openai")  -- not "truncated json mode" like Gemini

      local expected = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/text-event-stream/expected-output.json"))
      local expected_events = cjson.decode(expected)

      assert.same(events, expected_events)
    end)

    it("transforms application/vnd.amazon.eventstream (AWS) type", function()
      local input = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/streaming-chunk-formats/aws/input.bin"))
      local events = ai_shared.frame_to_events(input, "bedrock")

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

end)
