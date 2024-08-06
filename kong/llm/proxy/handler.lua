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
local strip = require("kong.tools.utils").strip

-- cloud auth/sdk providers
local GCP_SERVICE_ACCOUNT do
  GCP_SERVICE_ACCOUNT = os.getenv("GCP_SERVICE_ACCOUNT")
end

local GCP = require("resty.gcp.request.credentials.accesstoken")
local aws_config = require "resty.aws.config"  -- reads environment variables whilst available
local AWS = require("resty.aws")
local AWS_REGION do
  AWS_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
end
--


local EMPTY = {}

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
  __index = function(this_cache, plugin_config)
    if plugin_config.model.provider == "gemini" and
       plugin_config.auth and
       plugin_config.auth.gcp_use_service_account then

      ngx.log(ngx.NOTICE, "loading gcp sdk for plugin ", kong.plugin.get_id())

      local service_account_json = (plugin_config.auth and plugin_config.auth.gcp_service_account_json) or GCP_SERVICE_ACCOUNT

      local ok, gcp_auth = pcall(GCP.new, nil, service_account_json)
      if ok and gcp_auth then
        -- store our item for the next time we need it
        gcp_auth.service_account_json = service_account_json
        this_cache[plugin_config] = { interface = gcp_auth, error = nil }
        return this_cache[plugin_config]
      end

      return { interface = nil, error = "cloud-authentication with GCP failed" }

    elseif plugin_config.model.provider == "bedrock" then
      ngx.log(ngx.NOTICE, "loading aws sdk for plugin ", kong.plugin.get_id())
      local aws

      local region = plugin_config.model.options
                 and plugin_config.model.options.bedrock
                 and plugin_config.model.options.bedrock.aws_region
                  or AWS_REGION

      if not region then
        return { interface = nil, error = "AWS region not specified anywhere" }
      end

      local access_key_set = (plugin_config.auth and plugin_config.auth.aws_access_key_id)
                          or aws_config.global.AWS_ACCESS_KEY_ID
      local secret_key_set = plugin_config.auth and plugin_config.auth.aws_secret_access_key
                          or aws_config.global.AWS_SECRET_ACCESS_KEY

      aws = AWS({
        -- if any of these are nil, they either use the SDK default or
        -- are deliberately null so that a different auth chain is used
        region = region,
      })

      if access_key_set and secret_key_set then
        -- Override credential config according to plugin config, if set
        local creds = aws:Credentials {
          accessKeyId = access_key_set,
          secretAccessKey = secret_key_set,
        }

        aws.config.credentials = creds
      end

      this_cache[plugin_config] = { interface = aws, error = nil }

      return this_cache[plugin_config]
    end
  end,
})


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


local function handle_streaming_frame(conf)
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

  -- now handle each chunk/frame
  local chunk = ngx.arg[1]
  local finished = ngx.arg[2]

  if type(chunk) == "string" and chunk ~= "" then
    -- transform each one into flat format, skipping transformer errors
    -- because we have already 200 OK'd the client by now

    if (not finished) and (is_gzip) then
      chunk = kong_utils.inflate_gzip(ngx.arg[1])
    end

    local events = ai_shared.frame_to_events(chunk, conf.model.provider)

    if not events then
      -- usually a not-supported-transformer or empty frames.
      -- header_filter has already run, so all we can do is log it,
      -- and then send the client a readable error in a single chunk
      local response = ERROR__NOT_SET

      if is_gzip then
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
  -- free up the buffered body used in the access phase
  kong.ctx.shared.ai_request_body = nil

  local kong_ctx_plugin = kong.ctx.plugin

  if llm_state.is_response_transformer_skipped() then
    return
  end

  -- clear shared restricted headers
  for _, v in ipairs(ai_shared.clear_response_headers.shared) do
    kong.response.clear_header(v)
  end

  -- only act on 200 in first release - pass the unmodifed response all the way through if any failure
  if kong.response.get_status() ~= 200 then
    return
  end

  -- we use openai's streaming mode (SSE)
  if llm_state.is_streaming_mode() then
    -- we are going to send plaintext event-stream frames for ALL models
    kong.response.set_header("Content-Type", "text/event-stream")
    return
  end

  local response_body = kong.service.response.get_raw_body()
  if not response_body then
    return
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
  local route_type = conf.route_type

  -- if this is a 'streaming' request, we can't know the final
  -- result of the response body, so we just proceed to body_filter
  -- to translate each SSE event frame
  if not llm_state.is_streaming_mode() then
    local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
    if is_gzip then
      response_body = kong_utils.inflate_gzip(response_body)
    end

    if route_type == "preserve" then
      kong_ctx_plugin.parsed_response = response_body
    else
      local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
      if err then
        kong_ctx_plugin.ai_parser_error = true

        ngx.status = 500
        kong_ctx_plugin.parsed_response = cjson.encode({ error = { message = err } })

      elseif new_response_string then
        -- preserve the same response content type; assume the from_format function
        -- has returned the body in the appropriate response output format
        kong_ctx_plugin.parsed_response = new_response_string
      end
    end
  end

  ai_driver.post_request(conf)
end


function _M:body_filter(conf)
  local kong_ctx_plugin = kong.ctx.plugin

  -- if body_filter is called twice, then return
  if kong_ctx_plugin.body_called and not llm_state.is_streaming_mode() then
    return
  end

  local route_type = conf.route_type

  if llm_state.is_response_transformer_skipped() and (route_type ~= "preserve") then
    local response_body = llm_state.get_parsed_response()

    if not response_body and kong.response.get_status() == 200 then
      response_body = kong.service.response.get_raw_body()
      if not response_body then
        kong.log.warn("issue when retrieve the response body for analytics in the body filter phase.",
                      " Please check AI request transformer plugin response.")
      else
        local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
        if is_gzip then
          response_body = kong_utils.inflate_gzip(response_body)
        end
      end
    else
      kong.response.exit(500, "no response body found")
    end

    local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
    local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)

    if err then
      kong.log.warn("issue when transforming the response body for analytics in the body filter phase, ", err)

    elseif new_response_string then
      ai_shared.post_request(conf, new_response_string)
    end
  end

  if not llm_state.is_response_transformer_skipped() then
    if (kong.response.get_status() ~= 200) and (not kong_ctx_plugin.ai_parser_error) then
      return
    end

    if route_type ~= "preserve" then
      if llm_state.is_streaming_mode() then
        handle_streaming_frame(conf)
      else
      -- all errors MUST be checked and returned in header_filter
      -- we should receive a replacement response body from the same thread
        local original_request = kong_ctx_plugin.parsed_response
        local deflated_request = original_request

        if deflated_request then
          local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
          if is_gzip then
            deflated_request = kong_utils.deflate_gzip(deflated_request)
          end

          kong.response.set_raw_body(deflated_request)
        end

        -- call with replacement body, or original body if nothing changed
        local _, err = ai_shared.post_request(conf, original_request)
        if err then
          kong.log.warn("analytics phase failed for request, ", err)
        end
      end
    end
  end

  kong_ctx_plugin.body_called = true
end


function _M:access(conf)
  local kong_ctx_plugin = kong.ctx.plugin

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
      llm_state.set_request_body_table(request_table)
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

  kong_ctx_plugin.llm_model_requested = conf_m.model.name

  -- check the incoming format is the same as the configured LLM format
  if not multipart then
    local compatible, err = llm.is_compatible(request_table, route_type)
    if not compatible then
      llm_state.set_response_transformer_skipped()
      return bail(400, err)
    end
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
      llm_state.set_response_transformer_skipped()
      return bail(400, err)
    end
  end

  -- execute pre-request hooks for "all" drivers before set new body
  local ok, err = ai_shared.pre_request(conf_m, parsed_request_body)
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
    llm_state.set_response_transformer_skipped()
    kong.log.err("failed to configure request for AI service: ", err)
    return bail(500)
  end

  -- lights out, and away we go

end

return _M
