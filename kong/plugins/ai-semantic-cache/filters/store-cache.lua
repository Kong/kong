-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson")
local vectordb        = require("kong.llm.vectordb")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local parse_directive_header = require("kong.tools.http").parse_directive_header
local calculate_resource_ttl = require("kong.tools.http").calculate_resource_ttl


local _M = {
  NAME = "ai-semantic-cache-store-cache",
  STAGE = "RES_POST_PROCESSING",
  DESCRIPTION = "store the cache into vectordb",
}

local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors(_M.NAME)

-- Retrieves response Cache-Control directives
local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end

function _M:run(conf)
  local cache_status = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "cache_status")
  if cache_status == "Hit" or kong.response.get_source() ~= "service" or kong.service.response.get_status() ~= 200 or cache_status == "Bypass" then
    -- do nothing, cache hit or don't want to cache
    return true
  end

  local cc = res_cc()

  local response_body, source = get_global_ctx("response_body")
  if not response_body then
    -- do nothing, headers are already sent
    if get_global_ctx("stream_mode") then
      -- TODO
      kong.log.warn("ai-proxy or ai-proxy-advanced plugin is currently needed to cache streaming response")
    else
      kong.log.warn("No cached response found while caching response")
    end

    return true
  end

  kong.log.debug("caching response from source: ", source)
  local storage_ttl = conf.cache_control and calculate_resource_ttl(cc) or
                conf.cache_ttl

  local cache_key = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "cache_key")

  response_body = cjson.decode(response_body)
  response_body.id = cache_key

  local vectordb_namespace = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "vectordb_namespace")
  if not vectordb_namespace then
    kong.log.warn("No vectordb namespace found while storing cache")
    return true
  end

  local embeddings_vector = ai_plugin_ctx.get_namespaced_ctx("ai-semantic-cache-search-cache", "embeddings_vector")

  ngx.timer.at(0, function(premature, conf, embeddings, body, cache_key, storage_ttl)
    if premature then
      return
    end

    local vectordb_driver, err = vectordb.new(conf.vectordb.strategy, vectordb_namespace, conf.vectordb)
    if err then
      kong.log.warn("Unable to load the cache driver: ", err)
      return
    end

    if not embeddings then
      kong.log.warn("No able to cache as no embeddings")
      return
    end

    local _, err = vectordb_driver:insert(embeddings, body, cache_key, storage_ttl)
    if err then
      kong.log.warn("Unable to store response in the cache: ", err)
    end
    kong.log.debug("Response loaded in the cache ")
  end, conf, embeddings_vector, response_body, cache_key, storage_ttl)

  return true
end

return _M