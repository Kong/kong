local cjson = require "cjson.safe"
local stream_response_fuzzer = require "spec.03-plugins.38-ai-proxy.fuzz.stream_response"
local ai_shared = require("kong.llm.drivers.shared")

stream_response_fuzzer.setup(getfenv())
-- Used in Gemini
local assert_fn = function(expected, actual, msg)
  -- tables are random ordered, so we need to compare each serialized event
  assert.same(cjson.decode(expected.data), cjson.decode(actual.data), msg)
end
stream_response_fuzzer.run_case("gemini",
  "spec/fixtures/ai-proxy/unit/streaming-chunk-formats/gemini/input.json",
  "spec/fixtures/ai-proxy/unit/streaming-chunk-formats/gemini/expected-output.json",
  ai_shared._CONST.GEMINI_STREAM_CONTENT_TYPE,
  assert_fn
)
