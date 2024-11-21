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

local gzip = require("kong.tools.gzip")
local build_request = require("kong.llm.embeddings.utils").build_request
local sha256_hex    = require "kong.tools.sha256".sha256_hex

local MISTRALAI_EMBEDDINGS_URL = "https://api.mistral.ai/v1/embeddings"

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
function Driver:new(c, dimensions)
  c.model = c.model or {}
  c.model.options = c.model.options or {}
  return setmetatable({
    config = {
      model = c.model or {},
      auth = c.auth or {}
    },
    dimensions = dimensions, -- not used by mistralai
  }, Driver)
end

-- Generates the embeddings (vectors) for a given prompt
--
-- @param prompt the prompt to generate embeddings for
-- @return the API response containing the embeddings
-- @return nothing. throws an error if any
function Driver:generate(prompt)
  local embeddings_url = self.config.model.options and
                        self.config.model.options.upstream_url or
                        MISTRALAI_EMBEDDINGS_URL

  local cache_key = "mistral-url:" .. embeddings_url .. "model:" .. self.config.model.name .. "prompt:" .. prompt
  local cache_hex_key = sha256_hex(cache_key)
  if cache_hex_key == nil then
    return nil, nil, "failed to generate cache key"
  end

  if ngx.ctx.ai_embeddings_cache and ngx.ctx.ai_embeddings_cache[cache_hex_key] then
      return ngx.ctx.ai_embeddings_cache[cache_hex_key].embeddings, ngx.ctx.ai_embeddings_cache[cache_hex_key].tokens, nil
  end

  local body = {
    input           = prompt,
    model           = self.config.model.name,
    encoding_format = "float",
  }

  kong.log.debug("[mistral] generating embeddings for prompt")
  local httpc, err = http.new({
    ssl_verify = true,
    ssl_cafile = kong.configuration.lua_ssl_trusted_certificate_combined,
  })
  if not httpc then
    return nil, nil, err
  end

  local headers = {
    ["Content-Type"]    = "application/json",
    ["Accept-Encoding"] = "gzip",
  }

  embeddings_url, headers, body = build_request(self.config.auth, embeddings_url, headers, body)

  body, err = cjson.encode(body)
  if err then
    return nil, nil, err
  end

  local res, err = httpc:request_uri(embeddings_url, {
    method = "POST",
    headers = headers,
    body = body,
  })
  if not res then
    return nil, nil, string.format("failed to generate embeddings (%s): %s", embeddings_url, err)
  end
  if res.status ~= 200 then
    return nil, nil, string.format("unexpected embeddings response (%s): %s", embeddings_url, res.status)
  end

  local res_body = res.body
  if res.headers["Content-Encoding"] == "gzip" then
    res_body = gzip.inflate_gzip(res_body)
  end

  local embeddings_response, err = cjson.decode(res_body)
  if err then
    return nil, nil, err
  end

  if not embeddings_response.data or #embeddings_response.data == 0 then
    return nil, nil, "no embeddings found in response"
  end

  local embeddings_tokens = embeddings_response.usage and embeddings_response.usage.total_tokens or 0

  if not ngx.ctx.ai_embeddings_cache then
    ngx.ctx.ai_embeddings_cache = {}
  end

  -- save the embeddings in the context
  ngx.ctx.ai_embeddings_cache[cache_hex_key] = {
    tokens = embeddings_tokens,
    embeddings = embeddings_response.data[1].embedding,
    model = self.config.model.name,
    prompt = prompt,
  }

  return embeddings_response.data[1].embedding, embeddings_tokens, nil
end

--
-- module
--

return Driver
