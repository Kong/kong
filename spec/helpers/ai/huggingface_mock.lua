--
-- imports
--

local mocker = require("spec.fixtures.mocker")

local mock_huggingface_embeddings = require("spec.helpers.ai.embeddings_mock").mock_huggingface_embeddings

--
-- private vars
--

local api = "https://router.huggingface.co"
local embeddings_url = api .. "/hf-inference/models/distilbert-base-uncased/pipeline/feature-extraction"

--
-- private functions
--

local mock_request_router = function(_self, url, opts)
  if url == embeddings_url then
    return mock_huggingface_embeddings(opts)
  end

  return nil, "URL " .. url .. " is not supported by mocking"
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
