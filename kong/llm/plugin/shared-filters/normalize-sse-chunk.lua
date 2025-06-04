local buffer = require("string.buffer")
local cjson = require("cjson.safe")

local deflate_gzip = require("kong.tools.gzip").deflate_gzip
local strip = require("kong.tools.string").strip
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local ai_shared = require("kong.llm.drivers.shared")

local EMPTY = require("kong.tools.table").EMPTY

-- static messages
local ERROR__NOT_SET = 'data: {"error": true, "message": "empty or unsupported transformer response"}'


local _M = {
  NAME = "normalize-sse-chunk",
  STAGE = "STREAMING",
  DESCRIPTION = "transform the SSE chunk based on provider",
}

local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)

-- get the token text from an event frame
local function get_token_text(event_t)
  -- get: event_t.choices[1]
  local first_choice = ((event_t or EMPTY).choices or EMPTY)[1] or EMPTY
  -- return:
  --   - event_t.choices[1].delta.content
  --   - event_t.choices[1].text
  --   - ""
  local token_text = (first_choice.delta or EMPTY).content or first_choice.text or ""
  return (type(token_text) == "string" and token_text) or ""
end

local function handle_streaming_frame(conf, chunk, finished)

  local accept_gzip = get_global_ctx("accept_gzip")

  local events = ai_plugin_ctx.get_namespaced_ctx("parse-sse-chunk", "current_events")
  if type(chunk) == "string" and chunk ~= "" and not events then
    -- usually a not-supported-transformer or empty frames.
    -- header_filter has already run, so all we can do is log it,
    -- and then send the client a readable error in a single chunk
    local response = ERROR__NOT_SET

    if accept_gzip then
      response = deflate_gzip(response)
    end

    ngx.arg[1] = response
    ngx.arg[2] = true

    return
  end

  -- this is fine, we can continue
  if not events then
    return
  end

  -- make a re-usable frame_buffer
  local frame_buffer = buffer.new()

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- create or reuse a buffer to store each response token/frame, on first pass
  local body_buffer
  do
    local source
    body_buffer, source = get_global_ctx("sse_body_buffer")
    -- TODO: should we only collect when conf.logging.log_payloads is enabled?
    -- how do we know if this is false but some other filter will need the body?
    if conf.logging and conf.logging.log_payloads and not body_buffer then
      body_buffer = buffer.new()
      set_global_ctx("sse_body_buffer", body_buffer)
    else
      kong.log.debug("using existing body buffer created by: ", source)
    end
  end

  local finish_reason


  for _, event in ipairs(events) do
    -- TODO: currently only subset of driver follow the body, err, metadata pattern
    -- unify this so that it was always extracted from the body
    local model_t = ai_plugin_ctx.get_request_model_table_inuse()
    local formatted, _, metadata = ai_driver.from_format(event, model_t, "stream/" .. conf.route_type)

    if formatted and formatted ~= ai_shared._CONST.SSE_TERMINATOR then  -- only stream relevant frames back to the user
      -- append the "choice" to the buffer, for logging later. this actually works!
      local event_t, err = cjson.decode(formatted)

      if not err then
        if event_t.choices and #event_t.choices > 0 then
          finish_reason = event_t.choices[1].finish_reason
        end

    if formatted then
      if not blocked_msg
        or (formatted == ai_shared._CONST.SSE_TERMINATOR and not get_global_ctx("sample_event"))then
        frame_buffer:put("data: ")
        frame_buffer:put(formatted)
        frame_buffer:put("\n\n")

        -- either enabled in ai-proxy plugin, or required by other plugin
        if body_buffer then
          body_buffer:put(token_t)
        end
      end
    end

    if conf.logging and conf.logging.log_statistics and metadata then
      -- gemini metadata specifically, works differently
      if conf.model.provider == "gemini" then
        ai_plugin_o11y.metrics_set("llm_prompt_tokens_count", metadata.prompt_tokens or 0)
        ai_plugin_o11y.metrics_set("llm_completion_tokens_count", metadata.completion_tokens or 0)
      else
        ai_plugin_o11y.metrics_add("llm_prompt_tokens_count", metadata.prompt_tokens or 0)
        ai_plugin_o11y.metrics_add("llm_completion_tokens_count", metadata.completion_tokens or 0)
      end
    end
  end

  local response_frame = frame_buffer:get()
  -- TODO: disable gzip for SSE because it needs immediate flush for each chunk
  -- and seems nginx doesn't support it
  if not finished and accept_gzip and not get_global_ctx("stream_mode") then
    response_frame = deflate_gzip(response_frame)
  end

  -- only overwrite the response frame if we
  -- are not handling a "native" format
  if conf.llm_format and conf.llm_format == "openai" then
    ngx.arg[1] = response_frame
  end

  if finished then
    local response = body_buffer and body_buffer:get()

    local prompt_tokens_count = ai_plugin_o11y.metrics_get("llm_prompt_tokens_count")
    local completion_tokens_count = ai_plugin_o11y.metrics_get("llm_completion_tokens_count")

    if conf.logging and conf.logging.log_statistics then
      -- no metadata populated in the event streams, do our estimation
      if completion_tokens_count == 0 then
        -- incredibly loose estimate based on https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
        -- but this is all we can do until OpenAI fixes this...
        --
        -- essentially, every 4 characters is a token, with minimum of 1*4 per event
        completion_tokens_count = math.ceil(#strip(response) / 4)
        ai_plugin_o11y.metrics_set("llm_completion_tokens_count", completion_tokens_count)
      end
    end

    -- populate cost
    if conf.model.options and conf.model.options.input_cost and conf.model.options.output_cost then
      local cost = (prompt_tokens_count * conf.model.options.input_cost +
                    completion_tokens_count * conf.model.options.output_cost) / 1000000 -- 1 million
      ai_plugin_o11y.metrics_set("llm_usage_cost", cost)
    else
      ai_plugin_o11y.metrics_set("llm_usage_cost", 0)
    end

    local composite_response_t = {
      choices = {
        {
          finish_reason = finish_reason,
          index = 0,
          logprobs = cjson.null,
          message = {
            role = "assistant",
            content = response,
          },
        }
      },
      model = nil, -- TODO: populate this
      object = "chat.completion",
      response = (conf.logging or EMPTY).log_payloads and response,
      usage = {
        prompt_tokens = prompt_tokens_count,
        completion_tokens = completion_tokens_count,
        total_tokens = ai_plugin_o11y.metrics_get("llm_total_tokens_count"),
      }
    }

    local response, _ = cjson.encode(composite_response_t)
    set_global_ctx("response_body", response) -- to be consumed by other plugins

    ngx.arg[1] = nil
    if body_buffer then
      body_buffer:free()
    end
  end
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

  if get_global_ctx("preserve_mode") then
    return true
  end

  if ai_plugin_ctx.has_namespace("ai-proxy-advanced-balance") then
    conf = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target") or conf
  end

  -- TODO: check if ai-response-transformer let response.source become not service
  if kong.response.get_source() == "service" then

    handle_streaming_frame(conf, ngx.arg[1], ngx.arg[2])
  end

  return true
end

return _M
