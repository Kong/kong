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
      ["GOOD_FULL_RERANK"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/rerank.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/rerank"
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
      ["GOOD_RETRIE_AND_GENERATE_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/retrieveAndGenerateStream.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/retrieveAndGenerateStream"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "cohere.command-r-v1:0",
                  ["operation"] = "retrieve-and-generate-stream",
                },
              }
            end,
          },
        },
      },
      ["GOOD_RETRIE_AND_GENERATE"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/retrieveAndGenerate.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/retrieveAndGenerate"
            end,
            get_uri_captures = function()
              return {
                named = {
                  ["model"] = "cohere.command-r-v1:0",
                  ["operation"] = "retrieve-and-generate",
                },
              }
            end,
          },
        },
      },
      ["GOOD_CONVERSE"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/converse.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/model/cohere.command-r-v1%3A0/converse"
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
      ["GOOD_CONVERSE_STREAM"] = {
        INPUT_FILE = "spec/fixtures/ai-proxy/native/bedrock/request/converse-stream.json",
        CLEANUP_BEFORE_COMPARE = function(expected_response, real_response)
          expected_response.model = "cohere.command-r-v1:0"
          return expected_response, real_response
        end,
        MOCK_KONG = {
          request = {
            get_path = function()
              return "/model/cohere.command-r-v1%3A0/converse-stream"
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
    it(fmt("adapters.%s good full with rerank", adapter_name), function()
      if adapter_name == "bedrock" then
        local target_response = cjson.decode(pl_file.read("spec/fixtures/ai-proxy/native/bedrock/request/rerank.json"))

        local test_manifest = adapter_manifest.TESTS.GOOD_FULL_RERANK

        package.loaded[adapter_manifest.CLASS] = nil
        _G.TEST = true
        local adapter = require(adapter_manifest.CLASS)

        adapter = adapter:new()

        local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
        local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)
        assert.same(adapter.forward_path, "/rerank")
        assert.same(response.messages,  target_response.queries)
      end
    end)
    it(fmt("adapters.%s good retrieve and generate stream", adapter_name), function()
      if adapter_name == "bedrock" then
        local target_response = cjson.decode(pl_file.read("spec/fixtures/ai-proxy/native/bedrock/request/retrieveAndGenerateStream.json"))

        local test_manifest = adapter_manifest.TESTS.GOOD_RETRIE_AND_GENERATE_STREAM

        package.loaded[adapter_manifest.CLASS] = nil
        _G.TEST = true
        local adapter = require(adapter_manifest.CLASS)

        adapter = adapter:new()

        local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
        local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)
        assert.same(adapter.forward_path, "/retrieveAndGenerateStream")
        assert.same(response.prompt,  target_response.input.text)
        assert.same(response.stream, true)
      end
    end)
    it(fmt("adapters.%s good retrieve and generate", adapter_name), function()
      if adapter_name == "bedrock" then
        local target_response = cjson.decode(pl_file.read("spec/fixtures/ai-proxy/native/bedrock/request/retrieveAndGenerate.json"))

        local test_manifest = adapter_manifest.TESTS.GOOD_RETRIE_AND_GENERATE

        package.loaded[adapter_manifest.CLASS] = nil
        _G.TEST = true
        local adapter = require(adapter_manifest.CLASS)

        adapter = adapter:new()

        local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
        local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)
        assert.same(adapter.forward_path, "/retrieveAndGenerate")
        assert.same(response.prompt,  target_response.input.text)
        assert.same(response.stream, false)
      end
    end)

    it(fmt("adapters.%s good converse", adapter_name), function()
      if adapter_name == "bedrock" then

        local test_manifest = adapter_manifest.TESTS.GOOD_CONVERSE

        package.loaded[adapter_manifest.CLASS] = nil
        _G.TEST = true
        local adapter = require(adapter_manifest.CLASS)

        adapter = adapter:new()

        local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
        local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)
        assert.same(adapter.forward_path, "/model/%s/converse")
        assert.same(response.stream, false)
      end
    end)

    it(fmt("adapters.%s good converse stream", adapter_name), function()
      if adapter_name == "bedrock" then

        local test_manifest = adapter_manifest.TESTS.GOOD_CONVERSE_STREAM

        package.loaded[adapter_manifest.CLASS] = nil
        _G.TEST = true
        local adapter = require(adapter_manifest.CLASS)

        adapter = adapter:new()

        local request = cjson.decode(pl_file.read(test_manifest.INPUT_FILE))
        local response = adapter:to_kong_req(request, test_manifest.MOCK_KONG)
        assert.same(adapter.forward_path, "/model/%s/converse-stream")
        assert.same(response.stream, true)
      end
    end)
  end

end)
