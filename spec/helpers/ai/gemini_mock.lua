-- gemini_mock.lua
--
-- imports
--

local mocker = require("spec.fixtures.mocker")
local cjson = require("cjson.safe")

local mock_gemini_embeddings = require("spec.helpers.ai.embeddings_mock").mock_gemini_embeddings
local mock_vertex_embeddings = require("spec.helpers.ai.embeddings_mock").mock_vertex_embeddings

--
-- private vars
--

--
-- private functions
--

local mock_request_router = function(_self, url, opts)
  if string.find(url, "404") then
    return {
      status = 404,
      body = "404 response",
      headers = {},
    }
  end

  if string.find(url, "not%-json") then
    return {
      status = 200,
      body = "not a json",
      headers = {},
    }
  end

  if string.find(url, "missing%-embeddings") then
    return {
      status = 200,
      body = cjson.encode({
        predictions = { {
          embeddings = {
            statistics = {
              truncated = false,
              token_count = 8,
            },
          },
        } },
        metadata = {
          billableCharacterCount = 8,
        },
      }),
      headers = {},
    }
  end 

  if string.find(url, "%-aiplatform%.googleapis%.com/v1/projects/.+/locations/.+/publishers/.+/models/.+:predict") then
    return mock_vertex_embeddings(opts, url)
  end

  -- Public Gemini API pattern: https://generativelanguage.googleapis.com/v1beta/models/{model}:embedContent
  if string.find(url, "generativelanguage%.googleapis%.com/v1beta/models/.+:embedContent") then
    return mock_gemini_embeddings(opts, url)
  end

  return nil, "URL " .. url .. " is not supported by gemini mocking"
end

--
-- public functions
--

local function setup(finally)
  mocker.setup(finally, {
    modules = {
      { "resty.http", {
        new = function()
          return {
            request_uri = mock_request_router,
          }
        end,
      } },
    }
  })
end

--
-- module
--

return {
  -- functions
  setup = setup,
}
