-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local mocker = require("spec.fixtures.mocker")

local mock_embeddings = require("spec.helpers.ai.embeddings_mock").mock_embeddings

--
-- private vars
--

local api = "https://api.mistral.ai"
local embeddings_url = api .. "/v1/embeddings"

--
-- private functions
--

local mock_request_router = function(_self, url, opts)
  if not string.find("^" .. url, api) then
    return nil, "what are you doing?"
  end

  if url == embeddings_url then
    return mock_embeddings(opts)
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
