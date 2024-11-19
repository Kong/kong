-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local inflate_gzip = require("kong.tools.gzip").inflate_gzip

local _M = {
  NAME = "parse-json-response",
  STAGE = "RES_INTROSPECTION",
  DESCRIPTION = "parse the JSON response body",
}

local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)


function _M:run(_)
  ai_plugin_o11y.record_request_end()

  if get_global_ctx("response_body") or get_global_ctx("stream_mode") or kong.response.get_source() ~= "service" then
    return true
  end

  local response_body = kong.service.response.get_raw_body()

  if response_body and kong.service.response.get_header("Content-Encoding") == "gzip" then
    response_body = inflate_gzip(response_body)
  end

  set_global_ctx("response_body", response_body)

  local t, err
  if response_body then
    t, err = cjson.decode(response_body)
    if err then
      kong.log.warn("failed to decode response body for usage introspection: ", err)
    end

    if t and t.usage and t.usage.prompt_tokens then
      ai_plugin_o11y.metrics_set("llm_prompt_tokens_count", t.usage.prompt_tokens)
    end

    if t and t.usage and t.usage.completion_tokens then
      ai_plugin_o11y.metrics_set("llm_completion_tokens_count", t.usage.completion_tokens)
    end
  end

  return true
end

return _M