-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local ai_plugin_ctx = require "kong.llm.plugin.ctx"
local ai_plugin_o11y = require "kong.llm.plugin.observability"
local ratelimiting = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".ratelimiting
local id_lookup = require "kong.plugins.ai-rate-limiting-advanced.ratelimiting".id_lookup


local _M = {
  NAME = "ai-rate-limiting-advanced-increment-counter",
  STAGE = "RES_POST_PROCESSING",
  DESCRIPTION = "increment counter based on metrics collected by other plugins",
}

local function add_numbers(ta, tb)
  if not ta or not tb then
    return ta or tb
  end

  for k, v in pairs(tb) do
    ta[k] = (ta[k] or 0) + v
  end

  return ta
end


-- this is way too complex :(
local function collect_usage(conf)
  local usages = {}
  -- proxy usage
  do
    local provider_name
    local model_t = ai_plugin_ctx.get_request_model_table_inuse()
    provider_name = model_t and model_t.provider

    if provider_name then
      usages[provider_name] = {
        cost = ai_plugin_o11y.metrics_get("llm_usage_cost") or 0,
        total_tokens = ai_plugin_o11y.metrics_get("llm_total_tokens_count") or 0,
        prompt_tokens = ai_plugin_o11y.metrics_get("llm_prompt_tokens_count") or 0,
        completion_tokens = ai_plugin_o11y.metrics_get("llm_completion_tokens_count") or 0,
      }
    end
  end

  -- transformer usage
  for _, what in ipairs({"request", "response"}) do
    local ns = string.format("ai-%s-transformer-transform-%s", what, what)
    if ai_plugin_ctx.has_namespace(ns) then
      local model_t = ai_plugin_ctx.get_namespaced_ctx(ns, "model")
      local provider_name = model_t and model_t.provider
      if provider_name then
        local prompt_tokens_count = ai_plugin_ctx.get_namespaced_ctx(ns, "llm_prompt_tokens_count") or 0
        local completion_tokens_count = ai_plugin_ctx.get_namespaced_ctx(ns, "llm_completion_tokens_count") or 0
        usages[provider_name] = add_numbers(usages[provider_name], {
          cost = ai_plugin_ctx.get_namespaced_ctx(ns, "llm_usage_cost") or 0,
          total_tokens = prompt_tokens_count + completion_tokens_count,
          prompt_tokens = prompt_tokens_count,
          completion_tokens = completion_tokens_count,
        })
      end
    end
  end

  return usages
end


function _M:run(conf)
  local key = id_lookup[conf.identifier](conf)

  -- legacy logic, if authenticated consumer or credential is not found
  -- use the IP
  if not key then
    key = id_lookup["ip"]()
  end

  local plugin_id = conf.__plugin_id
  local window_type = conf.window_type

  local usages = collect_usage(conf)

  local has_at_least_one_cost = false

  for _, provider_config in ipairs(conf.llm_providers) do

    local provider = provider_config.name
    local namespace_provider = provider .. ":" .. plugin_id
    local current_window = tonumber(provider_config.window_size)

    local query_cost = 0
    local cost_t = usages[provider]
    if cost_t then
      query_cost = cost_t[conf.tokens_count_strategy]
    end
    -- the cost for requestPrompt is already increased during limit-request

    if query_cost and query_cost > 0 then
      has_at_least_one_cost = true
    else
      kong.log.debug("No " .. conf.tokens_count_strategy .. " data for the provider " .. provider .. " in the request")
    end

    -- we increment all window even if we have exceeded any rate,
    -- as the ai requests has already been sent in body filter phase
    -- this part won't be called if we block the request in access phase
    local _ = ratelimiting.increment(key, current_window, query_cost, namespace_provider,
                                    window_type == "fixed" and 0 or nil)
  end

  if not has_at_least_one_cost then
    kong.log.warn("No query cost data for any configured provider in the request")
  end

  return true
end

return _M