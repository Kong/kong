local cjson = require "cjson.safe"
local stream_response_fuzzer = require "spec.03-plugins.38-ai-proxy.fuzz.stream_response"

stream_response_fuzzer.setup(getfenv())
-- Used in Gemini
local assert_fn = function(expected, actual, msg)
  -- tables are random ordered, so we need to compare each serialized event
  assert.same(cjson.decode(expected.data), cjson.decode(actual.data), msg)
end
stream_response_fuzzer.run_case("cohere",
  "spec/fixtures/ai-proxy/unit/streaming-chunk-formats/cohere/input.json",
  "spec/fixtures/ai-proxy/unit/streaming-chunk-formats/cohere/expected-output.json",
  "application/stream+json",
  assert_fn
)
