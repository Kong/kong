-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson")

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local ai_shared = require("kong.llm.drivers.shared")

local _M = {
  NAME = "normalize-json-response",
  STAGE = "RES_TRANSFORMATION",
  DESCRIPTION = "transform the JSON response body into a format suitable for the AI model",
}

local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)

local function transform_body(conf)
  local err
  local route_type = conf.route_type
  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- clear driver specific headers
  -- TODO: move this to a better place
  ai_driver.post_request(conf)

  local response_body = get_global_ctx("response_body")
  if not response_body then
    err = "no response body found when transforming response"

  elseif route_type ~= "preserve" then
    response_body, err = ai_driver.from_format(response_body, conf.model, route_type)

    if err then
      kong.log.err("issue when transforming the response body for analytics: ", err)
    end
  end

  if err then
    ngx.status = 500
    response_body = cjson.encode({ error = { message = err }})
  end

  set_global_ctx("response_body", response_body) -- to be sent out later or consumed by other plugins
end

function _M:run(conf)
  if kong.response.get_source() ~= "service" or kong.service.response.get_status() ~= 200 then
    return true
  end

  if ai_plugin_ctx.has_namespace("ai-request-transformer-transform-request") and
    ai_plugin_ctx.get_namespaced_ctx("ai-request-transformer-transform-request", "transformed") then
    return true
  end

  if ai_plugin_ctx.has_namespace("ai-response-transformer-transform-response") and
    ai_plugin_ctx.get_namespaced_ctx("ai-response-transformer-transform-response", "transformed") then
    return true
  end

  if ai_plugin_ctx.has_namespace("ai-proxy-advanced-balance") then
    conf = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target") or conf
  end

  -- if not streaming, prepare the response body buffer
  -- this must be called before sending any response headers so that
  -- we can modify status code if needed
  if not get_global_ctx("stream_mode") then
    transform_body(conf)
  end

  -- populate cost
  if conf.model.options and conf.model.options.input_cost and conf.model.options.output_cost then
    local cost = (ai_plugin_o11y.metrics_get("llm_prompt_tokens_count") * conf.model.options.input_cost +
                  ai_plugin_o11y.metrics_get("llm_completion_tokens_count") * conf.model.options.output_cost) / 1000000 -- 1 million
    ai_plugin_o11y.metrics_set("llm_usage_cost", cost)
  else
    ai_plugin_o11y.metrics_set("llm_usage_cost", 0)
  end

  -- clear shared restricted headers
  for _, v in ipairs(ai_shared.clear_response_headers.shared) do
    kong.response.clear_header(v)
  end


  if ngx.var.http_kong_debug or conf.model_name_header then
    local model_t = ai_plugin_ctx.get_request_model_table_inuse()
    assert(model_t and model_t.name, "model name is missing")
    kong.response.set_header("X-Kong-LLM-Model", conf.model.provider .. "/" .. model_t.name)
  end

  return true
end

return _M