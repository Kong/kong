-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local cjson = require("cjson.safe")
local http = require("resty.http")

local deep_copy = require("kong.tools.table").deep_copy
local gzip = require("kong.tools.gzip")

--
-- vars
--

local embeddings_url = "https://api.mistral.ai/v1/embeddings"

--
-- driver object
--

-- Driver is an interface for a mistralai embeddings driver.
local Driver = {}
Driver.__index = Driver

-- Constructs a new Driver
--
-- @param provided_embeddings_config embeddings driver configuration
-- @param dimensions the number of dimensions for generating embeddings
-- @return the Driver object
function Driver:new(provided_embeddings_config, dimensions)
  local driver_config = deep_copy(provided_embeddings_config)
  driver_config.dimensions = dimensions
  return setmetatable(driver_config, Driver)
end

-- Generates the embeddings (vectors) for a given prompt
--
-- @param prompt the prompt to generate embeddings for
-- @return the API response containing the embeddings
-- @return nothing. throws an error if any
function Driver:generate(prompt)
  local body, err = cjson.encode({
    input           = prompt,
    model           = self.model,
    encoding_format = "float",
  })
  if err then
    return nil, err
  end

  kong.log.debug("[mistralai] generating embeddings for prompt")
  local httpc = http.new({
    ssl_verify = true,
    ssl_cafile = kong.configuration.lua_ssl_trusted_certificate_combined,
  })
  local res, err = httpc:request_uri(embeddings_url, {
    method = "POST",
    headers = {
      ["Content-Type"]    = "application/json",
      ["Accept-Encoding"] = "gzip",
      ["Authorization"]   = "Bearer " .. self.auth.token,
    },
    body = body,
  })
  if not res then
    return nil, string.format("failed to generate embeddings (%s): %s", embeddings_url, err)
  end
  if res.status ~= 200 then
    return nil, string.format("unexpected embeddings response (%s): %s", embeddings_url, res.status)
  end

  local inflated_body = gzip.inflate_gzip(res.body)
  local embedding_response, err = cjson.decode(inflated_body)
  if err then
    return nil, err
  end

  if not embedding_response.data or #embedding_response.data == 0 then
    return nil, "no embeddings found in response"
  end

  return embedding_response.data[1].embedding, nil
end

--
-- module
--

return Driver
