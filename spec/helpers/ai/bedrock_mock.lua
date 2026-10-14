--
-- imports
--

local mocker = require("spec.fixtures.mocker")

local mock_bedrock_embeddings = require("spec.helpers.ai.embeddings_mock").mock_bedrock_embeddings
--
-- private vars
--

--
-- private functions
--

local mock_request_router = function(_self, url, opts)
  if string.find(url, "model/.+/invoke") then
    return mock_bedrock_embeddings(opts, url)
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
