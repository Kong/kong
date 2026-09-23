local cjson = require("cjson.safe")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")


local _M = {
  NAME = "serialize-analytics",
  STAGE = "RES_PRE_PROCESSING",
  DESCRIPTION = "serialize the llm stats",
}

local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors(_M.NAME)


function _M:run(conf)
  if not conf.logging or not conf.logging.log_statistics then
    return true
  end

  local provider_name, request_model
  do
    local model_t = ai_plugin_ctx.get_request_model_table_inuse()
    provider_name = model_t and model_t.provider or "UNSPECIFIED"
    request_model = model_t and model_t.name or "UNSPECIFIED"
  end

  local response_model
  do
    local response_body = get_global_ctx("response_body")
    if response_body then
      local adapter = get_global_ctx("llm_format_adapter")

      if adapter then
        -- native formats
        response_model = adapter:extract_response_model(response_body)
        if not response_model then
          kong.log.info("unable to extract model-used from response")
        end

      else
        -- openai formats
        local response_body_table, err = cjson.decode(response_body)
        if err then
          kong.log.info("failed to decode response body: ", err)
        end
        response_model = response_body_table and response_body_table.model
      end
    end

    if not response_model then
      response_model = request_model
    end
  end

  -- metadata
  local metadata = {
    plugin_id = conf.__plugin_id,
    provider_name = provider_name,
    request_model = request_model,
    response_model = response_model,
    -- this is somehow in metadata while tpot_latency is in usage. keep it as is for backward compatibility
    -- it should be fixed in 4.0 :(
    llm_latency = ai_plugin_o11y.metrics_get("llm_e2e_latency"),
  }

  -- TODO: make this better, right now only azure has this extra field
  if kong.ctx.plugin.ai_extra_meta and type(kong.ctx.plugin.ai_extra_meta) == "table" then
    for k, v in pairs(kong.ctx.plugin.ai_extra_meta) do
      metadata[k] = v
    end
  end

  kong.log.set_serialize_value(string.format("ai.%s.meta", ai_plugin_o11y.NAMESPACE), metadata)

  -- usage
  local usage = {
    time_per_token = ai_plugin_o11y.metrics_get("llm_tpot_latency"),
    prompt_tokens = ai_plugin_o11y.metrics_get("llm_prompt_tokens_count"),
    completion_tokens = ai_plugin_o11y.metrics_get("llm_completion_tokens_count"),
    total_tokens = ai_plugin_o11y.metrics_get("llm_total_tokens_count"),
    cost = ai_plugin_o11y.metrics_get("llm_usage_cost"),
  }
  kong.log.set_serialize_value(string.format("ai.%s.usage", ai_plugin_o11y.NAMESPACE), usage)


  -- payloads
  if conf.logging and conf.logging.log_payloads then
    -- can't use kong.service.get_raw_body because it also fall backs to get_body_file which isn't available in log phase
    kong.log.set_serialize_value(string.format("ai.%s.payload.request", ai_plugin_o11y.NAMESPACE), ngx.req.get_body_data())
    kong.log.set_serialize_value(string.format("ai.%s.payload.response", ai_plugin_o11y.NAMESPACE), get_global_ctx("response_body"))
  end


  return true
end

return _M
