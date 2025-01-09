local _M = {
  NAME = "normalize-response-header",
  STAGE = "REQ_POST_PROCESSING",
  DESCRIPTION = "normalize upstream response headers",
}

local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors("_base")

local FILTER_OUTPUT_SCHEMA = {
  stream_content_type = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

function _M:run(_)
  -- for error and exit response, just use plaintext headers
  if kong.response.get_source() == "service" then
    -- we use openai's streaming mode (SSE)
    if get_global_ctx("stream_mode") then
      -- we are going to send plaintext event-stream frames for ALL models,
      -- but we capture the original incoming content-type for the chunk-parser later.
      set_ctx("stream_content_type", kong.service.response.get_header("Content-Type"))
      kong.response.set_header("Content-Type", "text/event-stream")

      -- TODO: disable gzip for SSE because it needs immediate flush for each chunk
      -- and seems nginx doesn't support it
    elseif get_global_ctx("accept_gzip") then
      -- for gzip response, don't set content-length at all to align with upstream
      kong.response.clear_header("Content-Length")
      kong.response.set_header("Content-Encoding", "gzip")
    else
      kong.response.clear_header("Content-Encoding")
    end
  else
    kong.response.clear_header("Content-Encoding")
  end
end

return _M
