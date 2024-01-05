local PLUGIN_NAME = "ai-proxy"
local pl_file = require("pl.file")
local pl_replace = require("pl.stringx").replace
local cjson = require("cjson.safe")
local fmt = string.format


local FORMATS = {
  openai = {
    ["llm/v1/chat"] = {
      name = "gpt-4",
      provider = "openai",
      options = {
        max_tokens = 512,
        temperature = 0.5,
      },
    },
    ["llm/v1/completions"] = {
      name = "gpt-3.5-turbo-instruct",
      provider = "openai",
      options = {
        max_tokens = 512,
        temperature = 0.5,
      },
    },
  },
  cohere = {
    ["llm/v1/chat"] = {
      name = "command",
      provider = "cohere",
      options = {
        max_tokens = 512,
        temperature = 0.5,
      },
    },
    ["llm/v1/completions"] = {
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
  anthropic = {
    ["llm/v1/chat"] = {
      name = "claude-2",
      provider = "anthropic",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        top_p = 1.0,
      },
    },
    ["llm/v1/completions"] = {
      name = "claude-2",
      provider = "anthropic",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        top_p = 1.0,
      },
    },
  },
  azure = {
    ["llm/v1/chat"] = {
      name = "gpt-4",
      provider = "azure",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        top_p = 1.0,
      },
    },
    ["llm/v1/completions"] = {
      name = "gpt-3.5-turbo-instruct",
      provider = "azure",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        top_p = 1.0,
      },
    },
  },
  llama2 = {
    ["llm/v1/chat"] = {
      name = "llama2",
      provider = "llama2",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        llama2_format = "raw",
      },
    },
    ["llm/v1/completions"] = {
      name = "llama2",
      provider = "llama2",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        llama2_format = "raw",
      },
    },
  },
  mistral = {
    ["llm/v1/chat"] = {
      name = "mistral-tiny",
      provider = "openai",
      options = {
        max_tokens = 512,
        temperature = 0.5,
      },
    },
  },
}


describe(PLUGIN_NAME .. ": (unit)", function()

  for i, j in pairs(FORMATS) do

    describe(i .. " provider tests", function()

      for k, l in pairs(j) do

        ---- actual testing code begins here
        describe(k .. " format test", function()

          local actual_request_table
          local driver = require("kong.llm.drivers." .. i)


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
            actual_request_table, content_type, err = driver.to_format(request_table, l, k)
            assert.not_nil(content_type)
            assert.is_nil(err)

            -- load the expected outbound request to this provider
            local expected_request_json = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/expected-requests/%s/%s.json", i, pl_replace(k, "/", "-")))
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
            local virtual_response_json = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/real-responses/%s/%s.json", i, pl_replace(k, "/", "-")))

            -- convert to kong format (emulate on response phase hook)
            local actual_response_json, err = driver.from_format(virtual_response_json, l, k)
            assert.is_nil(err)

            local actual_response_table, err = cjson.decode(actual_response_json)
            assert.is_nil(err)

            -- load the expected response body
            local expected_response_json = pl_file.read(fmt("spec/fixtures/ai-proxy/unit/expected-responses/%s/%s.json", i, pl_replace(k, "/", "-")))
            local expected_response_table, err = cjson.decode(expected_response_json)
            assert.is_nil(err)

            -- compare the tables
            assert.same(actual_response_table.choices[1].message, expected_response_table.choices[1].message)
            assert.same(actual_response_table.model, expected_response_table.model)
          end)


        end)
      end
    end)
  end

  it("throws correct error when format is not supported", function()
    local driver = require("kong.llm.drivers.mistral")  -- one-shot, random example of provider with only prompt support
    
    local model_config = {
      route_type = "llm/v1/chatnopenotsupported",
      name = "mistral-tiny",
      provider = "mistral",
      options = {
        max_tokens = 512,
        temperature = 0.5,
      },
    }

    local request_json = pl_file.read("spec/fixtures/ai-proxy/unit/requests/llm-v1-chat.json")
    local request_table, err = cjson.decode(request_json)
    assert.is_falsy(err)

    -- send it
    local actual_request_table, content_type, err = driver.to_format(request_table, model_config, model_config.route_type)
    assert.is_nil(actual_request_table)
    assert.is_nil(content_type)
    assert.equal(err, "no transformer for mistral://llm/v1/chatnopenotsupported")
  end)
end)
