local PLUGIN_NAME = "ai-proxy"
local pl_file = require("pl.file")
local cjson = require("cjson.safe")
local fmt = string.format


local _NATIVE_ADAPTERS = {
  bedrock = {
    CLASS = "kong.llm.adapters.bedrock",
    TESTS = {
      ["GOOD_FULL_NO_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/with-functions-and-chatter.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/bedrock/model/cohere.command-r-v1%3A0/converse"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "cohere.command-r-v1:0",
                  ["operation"] = "converse",
                },
              }
            end,
          },
        },
      },
      ["GOOD_FULL_WITH_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/with-functions-and-chatter.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/bedrock/model/cohere.command-r-v1%3A0/converse-stream"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "cohere.command-r-v1:0",
                  ["operation"] = "converse-stream",
                },
              }
            end,
          },
        },
      },
    },
  },
  gemini = {
    CLASS = "kong.llm.adapters.gemini",
    TESTS = {
      ["GOOD_FULL_NO_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/gemini/request/with-functions-and-chatter.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          for i, v in ipairs(expected_response.messages) do
            if v.tool_call_id then
              expected_response.messages[i].tool_call_id = nil
            end
            if v.tool_calls then
              for j, k in ipairs(v.tool_calls) do
                expected_response.messages[i].tool_calls[j].id = nil
              end
            end
          end

          for i, v in ipairs(real_response.messages) do
            if v.tool_calls then
              for j, k in ipairs(v.tool_calls) do
                real_response.messages[i].tool_calls[j]['function'].id = nil
              end
            end
          end

          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/v1/projects/fake-project-010101/locations/us-central1/publishers/google/models/gemini-1.5-pro:generateContent"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "gemini-1.5-pro",
                  ["operation"] = "generateContent",
                },
              }
            end,
          },
        },
      },
      ["GOOD_FULL_WITH_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/gemini/request/with-functions-and-chatter.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          for i, v in ipairs(expected_response.messages) do
            if v.tool_call_id then
              expected_response.messages[i].tool_call_id = nil
            end
            if v.tool_calls then
              for j, k in ipairs(v.tool_calls) do
                expected_response.messages[i].tool_calls[j].id = nil
              end
            end
          end

          for i, v in ipairs(real_response.messages) do
            if v.tool_calls then
              for j, k in ipairs(v.tool_calls) do
                real_response.messages[i].tool_calls[j]['function'].id = nil
              end
            end
          end

          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/v1/projects/fake-project-010101/locations/us-central1/publishers/google/models/gemini-1.5-pro:streamGenerateContent"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "gemini-1.5-pro",
                  ["operation"] = "streamGenerateContent",
                },
              }
            end,
          },
        },
      },
    },
  },
}

local COMPARE_OUTPUT_FILES = {
  ["GOOD_FULL_NO_STREAM"] = "spec/fixtures/ai-proxy/native/target/target-openai-complete.json",
  ["GOOD_FULL_WITH_STREAM"] = "spec/fixtures/ai-proxy/native/target/target-openai-complete-stream.json",
}


describe(PLUGIN_NAME .. ": (unit)", function()
  lazy_setup(function()
    package.loaded["kong.llm.drivers.shared"] = nil
    _G.TEST = true
  end)

  lazy_teardown(function()
    _G.TEST = nil
  end)

  for adapter_name, adapter_manifest in pairs(_NATIVE_ADAPTERS) do
    it(fmt("adapters.%s good full no stream", adapter_name), function()
      local target_response = cjson.decode(pl_file.read(COMPARE_OUTPUT_FILES.GOOD_FULL_NO_STREAM))

      local test_manifest = adapter_manifest.TESTS.GOOD_FULL_NO_STREAM

      package.loaded[adapter_manifest.CLASS] = nil
      _G.TEST = true
      local adapter = require(adapter_manifest.CLASS)

      adapter = adapter:new()

      local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
      local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)

      if test_manifest.CLEANUP_BEFORE_COMPARE then
        target_response, response = test_manifest.CLEANUP_BEFORE_COMPARE(target_response, response)
      end

      assert.same(target_response, response)
    end)

    it(fmt("adapters.%s good full with stream", adapter_name), function()
      local target_response = cjson.decode(pl_file.read(COMPARE_OUTPUT_FILES.GOOD_FULL_WITH_STREAM))

      local test_manifest = adapter_manifest.TESTS.GOOD_FULL_WITH_STREAM

      package.loaded[adapter_manifest.CLASS] = nil
      _G.TEST = true
      local adapter = require(adapter_manifest.CLASS)

      adapter = adapter:new()

      local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
      local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)

      if test_manifest.CLEANUP_BEFORE_COMPARE then
        target_response, response = test_manifest.CLEANUP_BEFORE_COMPARE(target_response, response)
      end

      assert.same(target_response, response)
    end)
  end

end)
