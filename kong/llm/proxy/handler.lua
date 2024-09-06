-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_shared = require("kong.llm.drivers.shared")
local llm = require("kong.llm")
local llm_state = require("kong.llm.state")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")
local buffer = require "string.buffer"
local strip = require("kong.tools.string").strip
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy


local EMPTY = require("kong.tools.table").EMPTY

local _M = {}

local function bail(code, msg)
  if code == 400 and msg then
    kong.log.info(msg)
  end

  if ngx.get_phase() ~= "balancer" then
    return kong.response.exit(code, msg and { error = { message = msg } } or nil)
  end
end


-- static messages
local ERROR__NOT_SET = 'data: {"error": true, "message": "empty or unsupported transformer response"}'


local _KEYBASTION = setmetatable({}, {
  __mode = "k",
  __index = ai_shared.cloud_identity_function,
})


local function accept_gzip()
  return not not kong.ctx.plugin.accept_gzip
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

    if not finished and kong.service.response.get_header("Content-Encoding") == "gzip" then
      chunk = kong_utils.inflate_gzip(chunk)
    end

    local events = ai_shared.frame_to_events(chunk, conf.model.provider)

    if not events then
      -- usually a not-supported-transformer or empty frames.
      -- header_filter has already run, so all we can do is log it,
      -- and then send the client a readable error in a single chunk
      local response = ERROR__NOT_SET

      if accept_gzip() then
        response = kong_utils.deflate_gzip(response)
      end

      ngx.arg[1] = response
      ngx.arg[2] = true

      return
    end

    for _, event in ipairs(events) do
      local formatted, _, metadata = ai_driver.from_format(event, conf.model, "stream/" .. conf.route_type)

      local event_t = nil
      local token_t = nil
      local err

      if formatted then  -- only stream relevant frames back to the user
        if conf.logging and conf.logging.log_payloads and (formatted ~= ai_shared._CONST.SSE_TERMINATOR) then
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
            if formatted ~= ai_shared._CONST.SSE_TERMINATOR then
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
        framebuffer:put((formatted ~= ai_shared._CONST.SSE_TERMINATOR) and "\n\n" or "")
      end

      if conf.logging and conf.logging.log_statistics and metadata then
        -- gemini metadata specifically, works differently
        if conf.model.provider == "gemini" then
          kong_ctx_plugin.ai_stream_completion_tokens = metadata.completion_tokens or 0
          kong_ctx_plugin.ai_stream_prompt_tokens = metadata.prompt_tokens or 0
        else
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
  end

  local response_frame = framebuffer:get()
  -- TODO: disable gzip for SSE because it needs immediate flush for each chunk
  -- and seems nginx doesn't support it
  if not finished and accept_gzip() and not llm_state.is_streaming_mode() then
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

local function transform_body(conf)
  local route_type = conf.route_type
  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- Note: below even if we are told not to do response transform, we still need to do
  -- get the body for analytics

  -- try parsed response from other plugin first
  local response_body = llm_state.get_parsed_response()
  -- read from upstream if it's not been parsed/transformed by other plugins
  if not response_body then
    response_body = kong.service.response.get_raw_body()

    if response_body and kong.service.response.get_header("Content-Encoding") == "gzip" then
      response_body = kong_utils.inflate_gzip(response_body)
    end
  end

  local err

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

  else
    ai_shared.post_request(conf, response_body)
  end

  if accept_gzip() then
    response_body = kong_utils.deflate_gzip(response_body)
  end

  kong.ctx.plugin.buffered_response_body = response_body
end

function _M:header_filter(conf)
  -- free up the buffered body used in the access phase
  llm_state.set_request_body_table(nil)

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
  ai_driver.post_request(conf)

  if llm_state.should_disable_ai_proxy_response_transform() then
    return
  end

  -- only act on 200 in first release - pass the unmodifed response all the way through if any failure
  if kong.response.get_status() ~= 200 then
    return
  end

  -- if not streaming, prepare the response body buffer
  -- this must be called before sending any response headers so that
  -- we can modify status code if needed
  if not llm_state.is_streaming_mode() then
    transform_body(conf)
  end

  -- clear shared restricted headers
  for _, v in ipairs(ai_shared.clear_response_headers.shared) do
    kong.response.clear_header(v)
  end

  if ngx.var.http_kong_debug or conf.model_name_header then
    local name = conf.model.provider .. "/" .. (llm_state.get_request_model())
    kong.response.set_header("X-Kong-LLM-Model", name)
  end

  -- we use openai's streaming mode (SSE)
  if llm_state.is_streaming_mode() then
    -- we are going to send plaintext event-stream frames for ALL models
    kong.response.set_header("Content-Type", "text/event-stream")
    -- TODO: disable gzip for SSE because it needs immediate flush for each chunk
    -- and seems nginx doesn't support it
  else

    if accept_gzip() then
      kong.response.set_header("Content-Encoding", "gzip")
    else
      kong.response.clear_header("Content-Encoding")
    end
  end
end


-- body filter is only used for streaming mode; for non-streaming mode, everything
-- is already done in header_filter. This is because it would be too late to
-- send the status code if we are modifying non-streaming body in body_filter
function _M:body_filter(conf)
  if kong.service.response.get_status() ~= 200 then
    return
  end

  -- emit the full body if not streaming
  if not llm_state.is_streaming_mode() then
    ngx.arg[1] = kong.ctx.plugin.buffered_response_body
    ngx.arg[2] = true

    kong.ctx.plugin.buffered_response_body = nil
    return
  end

  if not llm_state.should_disable_ai_proxy_response_transform() and
      conf.route_type ~= "preserve" then

    handle_streaming_frame(conf, ngx.arg[1], ngx.arg[2])
  end
end


function _M:access(conf)
  local kong_ctx_plugin = kong.ctx.plugin
  -- record the request header very early, otherwise kong.serivce.request.set_header will polute it
  kong_ctx_plugin.accept_gzip = (kong.request.get_header("Accept-Encoding") or ""):match("%f[%a]gzip%f[%A]")

  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type

  kong_ctx_plugin.operation = route_type

  local multipart = false

  -- TODO: the access phase may be called mulitple times also in the balancer phase
  -- Refactor this function a bit so that we don't mess them in the same function
  local balancer_phase = ngx.get_phase() == "balancer"

  -- we may have received a replacement / decorated request body from another AI plugin
  local request_table = llm_state.get_replacement_response() -- not used
  if request_table then
    kong.log.debug("replacement request body received from another AI plugin")

  else
    -- first, calculate the coordinates of the request
    local content_type = kong.request.get_header("Content-Type") or "application/json"

    request_table = llm_state.get_request_body_table()
    if not request_table then
      if balancer_phase then
        error("Too late to read body", 2)
      end

      request_table = kong.request.get_body(content_type, nil, conf.max_request_body_size)
      llm_state.set_request_body_table(cycle_aware_deep_copy(request_table))
    end

    if not request_table then
      if not string.find(content_type, "multipart/form-data", nil, true) then
        return bail(400, "content-type header does not match request body, or bad JSON formatting")
      end

      multipart = true  -- this may be a large file upload, so we have to proxy it directly
    end
  end

  -- resolve the real plugin config values
  local conf_m, err = ai_shared.resolve_plugin_conf(kong.request, conf)
  if err then
    return bail(400, err)
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
      return bail(400, "cannot use own model - must be: " .. conf_m.model.name)
    end
  end

  -- model is stashed in the copied plugin conf, for consistency in transformation functions
  if not conf_m.model.name then
    return bail(400, "model parameter not found in request, nor in gateway configuration")
  end

  llm_state.set_request_model(conf_m.model.name)

  -- check the incoming format is the same as the configured LLM format
  local compatible, err = llm.is_compatible(request_table, route_type)
  if not multipart and not compatible then
    llm_state.disable_ai_proxy_response_transform()
    return bail(400, err)
  end

  -- check if the user has asked for a stream, and/or if
  -- we are forcing all requests to be of streaming type
  if request_table and request_table.stream or
     (conf_m.response_streaming and conf_m.response_streaming == "always") then
    request_table.stream = true

    -- this condition will only check if user has tried
    -- to activate streaming mode within their request
    if conf_m.response_streaming and conf_m.response_streaming == "deny" then
      return bail(400, "response streaming is not enabled for this LLM")
    end

    -- store token cost estimate, on first pass, if the
    -- provider doesn't reply with a prompt token count
    if (not kong.ctx.plugin.ai_stream_prompt_tokens) and (not ai_shared.streaming_has_token_counts[conf_m.model.provider]) then
      local prompt_tokens, err = ai_shared.calculate_cost(request_table or {}, {}, 1.8)
      if err then
        kong.log.err("unable to estimate request token cost: ", err)
        return bail(500)
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
    return bail(400, err)
  end

  -- transform the body to Kong-format for this provider/model
  local parsed_request_body, content_type, err
  if route_type ~= "preserve" and (not multipart) then
    -- transform the body to Kong-format for this provider/model
    parsed_request_body, content_type, err = ai_driver.to_format(request_table, conf_m.model, route_type)
    if err then
      llm_state.disable_ai_proxy_response_transform()
      return bail(400, err)
    end
  end

  -- execute pre-request hooks for "all" drivers before set new body
  local ok, err = ai_shared.pre_request(conf_m, parsed_request_body or request_table)
  if not ok then
    return bail(400, err)
  end

  if route_type ~= "preserve" and not balancer_phase then
    kong.service.request.set_body(parsed_request_body, content_type)
  end

  -- get the provider's cached identity interface - nil may come back, which is fine
  local identity_interface = _KEYBASTION[conf]

  if identity_interface and identity_interface.error then
    llm_state.set_response_transformer_skipped()
    kong.log.err("error authenticating with cloud-provider, ", identity_interface.error)
    return bail(500, "LLM request failed before proxying")
  end

  -- now re-configure the request for this operation type
  local ok, err = ai_driver.configure_request(conf_m,
               identity_interface and identity_interface.interface)
  if not ok then
    llm_state.disable_ai_proxy_response_transform()
    kong.log.err("failed to configure request for AI service: ", err)
    return bail(500)
  end

  -- lights out, and away we go

end

return _M
