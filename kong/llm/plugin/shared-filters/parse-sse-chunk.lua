local inflate_gzip = require("kong.tools.gzip").inflate_gzip
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_shared = require("kong.llm.drivers.shared")

local _M = {
  NAME = "parse-sse-chunk",
  STAGE = "STREAMING",
  DESCRIPTION = "parse the SSE chunk",
}

local FILTER_OUTPUT_SCHEMA = {
  current_events = "table",
}

local get_global_ctx, _ = ai_plugin_ctx.get_global_accessors(_M.NAME)
local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

local function handle_streaming_frame(conf, chunk, finished)

  local content_type = ai_plugin_ctx.get_namespaced_ctx("normalize-response-header", "stream_content_type")

  local normalized_content_type = content_type and content_type:sub(1, (content_type:find(";") or 0) - 1)
  if normalized_content_type and (not ai_shared._SUPPORTED_STREAMING_CONTENT_TYPES[normalized_content_type]) then
    return true
  end

  if type(chunk) == "string" and chunk ~= "" then
    -- transform each one into flat format, skipping transformer errors
    -- because we have already 200 OK'd the client by now

    if not finished and kong.service.response.get_header("Content-Encoding") == "gzip" then
      chunk = inflate_gzip(chunk)
    end

    local events = ai_shared.frame_to_events(chunk, normalized_content_type)
    if not events then
      -- unrecognized frame, need to reset the current events
      set_ctx("current_events", {})
      return
    end

    set_ctx("current_events", events)

    local body_buffer, source = get_global_ctx("sse_body_buffer")

    -- don't collect on this filter if it's not enabled or is already been handled by normalize-sse-chunk
    if not body_buffer or source == "normalize-sse-chunk" then
      return
    end

    kong.log.debug("using existing body buffer created by: ", source)

    -- TODO: implement the ability to decode the frame based on content type
  else
    -- empty frame, need to reset the current events
    set_ctx("current_events", {})
  end
end


function _M:run(conf)
  if kong.response.get_source() ~= "service" or kong.service.response.get_status() ~= 200 then
    return true
  end

  if ai_plugin_ctx.has_namespace("ai-proxy-advanced-balance") then
    conf = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target") or conf
  end

  -- TODO: check if ai-response-transformer let response.source become not service
  if not get_global_ctx("preserve_mode") then

    handle_streaming_frame(conf, ngx.arg[1], ngx.arg[2])
  end
  return true
end

return _M
