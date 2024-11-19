-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")


local _M = {
  NAME = "ai-semantic-serialize-analytics",
  STAGE = "RES_POST_PROCESSING",
  DESCRIPTION = "serialize the cache stats",
}

local SEARCH_CACHE_NS = "ai-semantic-cache-search-cache"


function _M:run(conf)
  local cache_status = ai_plugin_ctx.get_namespaced_ctx(SEARCH_CACHE_NS, "cache_status")
  cache_status = cache_status and string.lower(cache_status)

  local cache_metrics = {
    vector_db = conf.vectordb.driver,
    cache_status = cache_status,
    fetch_latency = ai_plugin_ctx.get_namespaced_ctx(SEARCH_CACHE_NS, "cache_fetch_latency") or 0,
    embeddings_latency = ai_plugin_ctx.get_namespaced_ctx(SEARCH_CACHE_NS, "embeddings_latency") or 0,
    embeddings_tokens = ai_plugin_ctx.get_namespaced_ctx(SEARCH_CACHE_NS, "embeddings_tokens_count") or 0,
    embeddings_provider = conf.embeddings.model.provider,
    embeddings_model = conf.embeddings.model.name,
  }

  local usage_cost = ai_plugin_o11y.metrics_get("llm_usage_cost")
  if cache_status == "hit" then
    cache_metrics.cost_savings = usage_cost
    kong.log.set_serialize_value(string.format("ai.%s.usage.cost", ai_plugin_o11y.NAMESPACE), 0)
    kong.log.set_serialize_value(string.format("ai.%s.usage.prompt_tokens", ai_plugin_o11y.NAMESPACE), 0)
    kong.log.set_serialize_value(string.format("ai.%s.usage.completion_tokens", ai_plugin_o11y.NAMESPACE), 0)
    kong.log.set_serialize_value(string.format("ai.%s.usage.total_tokens", ai_plugin_o11y.NAMESPACE), 0)
  end

  kong.log.set_serialize_value(string.format("ai.%s.cache", ai_plugin_o11y.NAMESPACE), cache_metrics)

  return true
end

return _M