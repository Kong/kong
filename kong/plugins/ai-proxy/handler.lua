local ai_shared = require("kong.llm.drivers.shared")
local llm = require("kong.llm")
local llm_state = require("kong.llm.state")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")
local kong_meta = require("kong.meta")
local buffer = require "string.buffer"
local strip = require("kong.tools.utils").strip


local EMPTY = {}


local _M = {
  PRIORITY = 770,
  VERSION = kong_meta.version
}



--- Return a 400 response with a JSON body. This function is used to
-- return errors to the client while also logging the error.
local function bad_request(msg)
  kong.log.info(msg)
  return kong.response.exit(400, { error = { message = msg } })
end



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
  -- make a re-usable framebuffer
  local framebuffer = buffer.new()
  local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  local kong_ctx_plugin = kong.ctx.plugin
  -- create a buffer to store each response token/frame, on first pass
  if (conf.logging or EMPTY).log_payloads and
     (not kong_ctx_plugin.ai_stream_log_buffer) then
    kong_ctx_plugin.ai_stream_log_buffer = buffer.new()
  end


  if type(chunk) == "string" and chunk ~= "" then
    -- transform each one into flat format, skipping transformer errors
    -- because we have already 200 OK'd the client by now

    if (not finished) and (is_gzip) then
      chunk = kong_utils.inflate_gzip(chunk)
    end

    local events = ai_shared.frame_to_events(chunk)

    for _, event in ipairs(events) do
      local formatted, _, metadata = ai_driver.from_format(event, conf.model, "stream/" .. conf.route_type)

      local event_t = nil
      local token_t = nil
      local err

      if formatted then  -- only stream relevant frames back to the user
        if conf.logging and conf.logging.log_payloads and (formatted ~= "[DONE]") then
          -- append the "choice" to the buffer, for logging later. this actually works!
          if not event_t then
            event_t, err = cjson.decode(formatted)
          end

          if not err then
            if not token_t then
              token_t = get_token_text(event_t)
            end

            kong_ctx_plugin.ai_stream_log_buffer:put(token_t)
          end
        end

        -- handle event telemetry
        if conf.logging and conf.logging.log_statistics then
          if not ai_shared.streaming_has_token_counts[conf.model.provider] then
            if formatted ~= "[DONE]" then
              if not event_t then
                event_t, err = cjson.decode(formatted)
              end

              if not err then
                if not token_t then
                  token_t = get_token_text(event_t)
                end

                -- incredibly loose estimate based on https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
                -- but this is all we can do until OpenAI fixes this...
                --
                -- essentially, every 4 characters is a token, with minimum of 1*4 per event
                kong_ctx_plugin.ai_stream_completion_tokens =
                    (kong_ctx_plugin.ai_stream_completion_tokens or 0) + math.ceil(#strip(token_t) / 4)
              end
            end
          end
        end

        framebuffer:put("data: ")
        framebuffer:put(formatted or "")
        framebuffer:put((formatted ~= "[DONE]") and "\n\n" or "")
      end

      if conf.logging and conf.logging.log_statistics and metadata then
        kong_ctx_plugin.ai_stream_completion_tokens =
          (kong_ctx_plugin.ai_stream_completion_tokens or 0) +
          (metadata.completion_tokens or 0)
          or kong_ctx_plugin.ai_stream_completion_tokens
        kong_ctx_plugin.ai_stream_prompt_tokens =
          (kong_ctx_plugin.ai_stream_prompt_tokens or 0) +
          (metadata.prompt_tokens or 0)
          or kong_ctx_plugin.ai_stream_prompt_tokens
      end
    end
  end

  local response_frame = framebuffer:get()
  if (not finished) and (is_gzip) then
    response_frame = kong_utils.deflate_gzip(response_frame)
  end

  ngx.arg[1] = response_frame

  if finished then
    local fake_response_t = {
      response = kong_ctx_plugin.ai_stream_log_buffer and kong_ctx_plugin.ai_stream_log_buffer:get(),
      usage = {
        prompt_tokens = kong_ctx_plugin.ai_stream_prompt_tokens or 0,
        completion_tokens = kong_ctx_plugin.ai_stream_completion_tokens or 0,
        total_tokens = (kong_ctx_plugin.ai_stream_prompt_tokens or 0)
                     + (kong_ctx_plugin.ai_stream_completion_tokens or 0),
      }
    }

    ngx.arg[1] = nil
    ai_shared.post_request(conf, fake_response_t)
    kong_ctx_plugin.ai_stream_log_buffer = nil
  end
end

function _M:header_filter(conf)
  if llm_state.should_disable_ai_proxy_response_transform() then
    return
  end

  -- only act on 200 in first release - pass the unmodifed response all the way through if any failure
  if kong.response.get_status() ~= 200 then
    return
  end

  -- clear shared restricted headers
  for _, v in ipairs(ai_shared.clear_response_headers.shared) do
    kong.response.clear_header(v)
  end

  -- we use openai's streaming mode (SSE)
  if llm_state.is_streaming_mode() then
    -- we are going to send plaintext event-stream frames for ALL models
    kong.response.set_header("Content-Type", "text/event-stream")
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
  ai_driver.post_request(conf)
end

local function body_filter_chunk(conf, chunk, eof)
  local route_type = conf.route_type

  if not llm_state.should_disable_ai_proxy_response_transform() and
      route_type ~= "preserve" and
      llm_state.is_streaming_mode() then

    handle_streaming_frame(conf, chunk, eof) -- conf, data, eof

  else
    -- otherwise whether we should transform the response or not, record it
    -- even though we are not going to transform it, we may need to do analytics
    if chunk then
      kong.plugin.ctx.cached_response = kong.plugin.ctx.cached_response .. chunk
      -- dismiss the original response if are going to transform later
      if not llm_state.should_disable_ai_proxy_response_transform() then
        ngx.arg[1] = nil
      end
    end
  end
end

local function body_filter_end(conf)
  local route_type = conf.route_type
  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  if route_type == "preserve" or llm_state.is_streaming_mode() then
    return
  end

  -- Note: below even if we are told not to do response transform, we still need to do
  -- get the body for analytics

  -- try parsed response from other plugin first
  local response_body = llm_state.get_parsed_response()
  -- fallback to our own cached response
  if not response_body and kong.plugin.ctx.cached_response then
    response_body = kong.plugin.ctx.cached_response
  end

  if not response_body then
    return kong.response.exit(500, "no response body")
  end
  local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
  if is_gzip then
    response_body = kong_utils.inflate_gzip(response_body)
  end

  local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
  if err then
    kong.log.warn("issue when transforming the response body for analytics in the body filter phase, ", err)
    ngx.status = 500

    new_response_string = cjson.encode({ error = { message = err }})
  elseif new_response_string then
    ai_shared.post_request(conf, new_response_string)
  end


  if not llm_state.should_disable_ai_proxy_response_transform() then
    if is_gzip then
      new_response_string = kong_utils.deflate_gzip(new_response_string)
    end

    kong.response.set_raw_body(new_response_string)
  end -- no need to handle else cases, the response body is unmodified
end


function _M:body_filter(conf)
  if kong.response.get_status() ~= 200 then
    return
  end

  local data, eof = ngx.arg[1], ngx.arg[2]
  body_filter_chunk(conf, data, eof)

  if eof then
    body_filter_end(conf)
  end
end


function _M:access(conf)
  local kong_ctx_plugin = kong.ctx.plugin

  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type

  kong_ctx_plugin.operation = route_type

  local multipart = false

  -- we may have received a replacement / decorated request body from another AI plugin
  local request_table = llm_state.get_replacement_response() -- not used
  if request_table then
    kong.log.debug("replacement request body received from another AI plugin")

  else
    -- first, calculate the coordinates of the request
    local content_type = kong.request.get_header("Content-Type") or "application/json"

    request_table = kong.request.get_body(content_type)

    if not request_table then
      if not string.find(content_type, "multipart/form-data", nil, true) then
        return bad_request("content-type header does not match request body")
      end

      multipart = true  -- this may be a large file upload, so we have to proxy it directly
    end
  end

  -- resolve the real plugin config values
  local conf_m, err = ai_shared.resolve_plugin_conf(kong.request, conf)
  if err then
    return bad_request(err)
  end

  -- copy from the user request if present
  if (not multipart) and (not conf_m.model.name) and (request_table.model) then
    if type(request_table.model) == "string" then
      conf_m.model.name = request_table.model
    end
  elseif multipart then
    conf_m.model.name = "NOT_SPECIFIED"
  end

  -- check that the user isn't trying to override the plugin conf model in the request body
  if request_table and request_table.model and type(request_table.model) == "string" and request_table.model ~= "" then
    if request_table.model ~= conf_m.model.name then
      return bad_request("cannot use own model - must be: " .. conf_m.model.name)
    end
  end

  -- model is stashed in the copied plugin conf, for consistency in transformation functions
  if not conf_m.model.name then
    return bad_request("model parameter not found in request, nor in gateway configuration")
  end

  kong_ctx_plugin.llm_model_requested = conf_m.model.name

  -- check the incoming format is the same as the configured LLM format
  local compatible, err = llm.is_compatible(request_table, route_type)
  if not compatible then
    llm_state.disable_ai_proxy_response_transform()
    return bad_request(err)
  end

  -- check if the user has asked for a stream, and/or if
  -- we are forcing all requests to be of streaming type
  if request_table and request_table.stream or
     (conf_m.response_streaming and conf_m.response_streaming == "always") then
    request_table.stream = true

    -- this condition will only check if user has tried
    -- to activate streaming mode within their request
    if conf_m.response_streaming and conf_m.response_streaming == "deny" then
      return bad_request("response streaming is not enabled for this LLM")
    end

    -- store token cost estimate, on first pass
    if not kong_ctx_plugin.ai_stream_prompt_tokens then
      local prompt_tokens, err = ai_shared.calculate_cost(request_table or {}, {}, 1.8)
      if err then
        kong.log.err("unable to estimate request token cost: ", err)
        return kong.response.exit(500)
      end

      kong_ctx_plugin.ai_stream_prompt_tokens = prompt_tokens
    end

    -- specific actions need to skip later for this to work
    llm_state.set_streaming_mode()

  else
    kong.service.request.enable_buffering()
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- execute pre-request hooks for this driver
  local ok, err = ai_driver.pre_request(conf_m, request_table)
  if not ok then
    return bad_request(err)
  end

  -- transform the body to Kong-format for this provider/model
  local parsed_request_body, content_type, err
  if route_type ~= "preserve" and (not multipart) then
    -- transform the body to Kong-format for this provider/model
    parsed_request_body, content_type, err = ai_driver.to_format(request_table, conf_m.model, route_type)
    if err then
      llm_state.disable_ai_proxy_response_transform()
      return bad_request(err)
    end
  end

  -- execute pre-request hooks for "all" drivers before set new body
  local ok, err = ai_shared.pre_request(conf_m, parsed_request_body)
  if not ok then
    return bad_request(err)
  end

  if route_type ~= "preserve" then
    kong.service.request.set_body(parsed_request_body, content_type)
  end

  -- now re-configure the request for this operation type
  local ok, err = ai_driver.configure_request(conf_m)
  if not ok then
    llm_state.disable_ai_proxy_response_transform()
    kong.log.err("failed to configure request for AI service: ", err)
    return kong.response.exit(500)
  end

  -- lights out, and away we go

end


return _M
