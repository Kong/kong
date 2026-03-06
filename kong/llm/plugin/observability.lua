
local _M = {
  NAMESPACE = "proxy",
}

-- metrics

-- global metrics
local metrics_schema = {
  llm_tpot_latency = true,
  llm_e2e_latency = true,
  llm_prompt_tokens_count = true,
  llm_completion_tokens_count = true,
  llm_total_tokens_count = true,
  llm_usage_cost = true,
}

function _M.metrics_register(key)
  if metrics_schema[key] then
    error("key already registered: " .. key, 2)
  end

  metrics_schema[key] = true
  return true
end

local function get_metrics_ctx()
  local ctx = ngx.ctx.ai_llm_metrics
  if not ctx then
    ctx = {}
    ngx.ctx.ai_llm_metrics = ctx
  end

  return ctx
end

function _M.metrics_set(key, value)
  if not metrics_schema[key] then
    error("metrics key not registered: " .. key, 2)
  end

  local ctx = get_metrics_ctx()

  ctx[key] = value
  return value
end


function _M.metrics_add(key, increment)
  if not metrics_schema[key] then
    error("metrics key not registered: " .. key, 2)
  end

  local ctx = get_metrics_ctx()

  local value = ctx[key] or 0
  value = value + increment
  ctx[key] = value
  return value
end


function _M.metrics_get(key, skip_calculation)
  if not metrics_schema[key] then
    error("metrics key not registered: " .. key, 2)
  end

  local metrics = get_metrics_ctx()

  -- process automatic calculation
  if not metrics[key] and not skip_calculation then
    if key == "llm_tpot_latency" then
      local llm_completion_tokens_count = _M.metrics_get("llm_completion_tokens_count")
      if llm_completion_tokens_count  > 0 then
        return _M.metrics_get("llm_e2e_latency") / llm_completion_tokens_count
      end
      return 0
    elseif key == "llm_total_tokens_count" then
      local total = _M.metrics_get("llm_total_tokens_count", true)
      if total then
        return total
      end

      local prompt = _M.metrics_get("llm_prompt_tokens_count") or 0
      local completion = _M.metrics_get("llm_completion_tokens_count") or 0
      return prompt + completion
    end
  end

  return metrics[key] or 0
end

function _M.record_request_start()
  if ngx.ctx.ai_llm_request_start_time then
    return true
  end

  ngx.update_time()
  ngx.ctx.ai_llm_request_start_time = ngx.now()

  return true
end

function _M.record_request_end()
  local start = ngx.ctx.ai_llm_request_start_time
  if not start then
    return 0
  end

  ngx.update_time()
  local latency = ngx.now() - start
  _M.metrics_set("llm_e2e_latency", math.floor(latency * 1000))
  return latency
end

return _M
