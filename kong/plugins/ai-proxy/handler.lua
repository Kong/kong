local _M = {}

-- imports
local ai_shared = require("kong.llm.drivers.shared")
local ai_module = require("kong.llm")
local llm = require("kong.llm")
local cjson = require("cjson.safe")
local kong_utils = require("kong.tools.gzip")
local kong_meta = require("kong.meta")
local buffer = require "string.buffer"
local strip = require("kong.tools.utils").strip
--


_M.PRIORITY = 770
_M.VERSION = kong_meta.version


-- reuse this table for error message response
local ERROR_MSG = { error = { message = "" } }


local function bad_request(msg)
  kong.log.warn(msg)
  ERROR_MSG.error.message = msg

  return kong.response.exit(400, ERROR_MSG)
end


local function internal_server_error(msg)
  kong.log.err(msg)
  ERROR_MSG.error.message = msg

  return kong.response.exit(500, ERROR_MSG)
end

local function get_token_text(event_t)
  -- chat
  return
    event_t and
    event_t.choices and
    #event_t.choices > 0 and
    event_t.choices[1].delta and
    event_t.choices[1].delta.content

    or

  -- completions
    event_t and
    event_t.choices and
    #event_t.choices > 0 and
    event_t.choices[1].text

    or ""
end

local function handle_streaming_frame(conf)
  -- make a re-usable framebuffer
  local framebuffer = buffer.new()
  local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- create a buffer to store each response token/frame, on first pass
  if conf.logging
       and conf.logging.log_payloads
       and (not kong.ctx.plugin.ai_stream_log_buffer) then
    kong.ctx.plugin.ai_stream_log_buffer = buffer.new()
  end

  -- now handle each chunk/frame
  local chunk = ngx.arg[1]
  local finished = ngx.arg[2]

  if type(chunk) == "string" and chunk ~= "" then
    -- transform each one into flat format, skipping transformer errors
    -- because we have already 200 OK'd the client by now

    if (not finished) and (is_gzip) then
      event = kong_utils.inflate_gzip(chunk)
    end

    local events = ai_shared.frame_to_events(chunk)

    for _, event in ipairs(events) do
      local formatted, _, metadata = ai_driver.from_format(event, conf.model, "stream/" .. conf.route_type)

      local event_t, token_t, err

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

            kong.ctx.plugin.ai_stream_log_buffer:put(token_t)
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
                kong.ctx.plugin.ai_stream_completion_tokens =
                    (kong.ctx.plugin.ai_stream_completion_tokens or 0) + math.ceil(#strip(token_t) / 4)
              end
            end

          elseif metadata then
            kong.ctx.plugin.ai_stream_completion_tokens = metadata.completion_tokens or kong.ctx.plugin.ai_stream_completion_tokens
            kong.ctx.plugin.ai_stream_prompt_tokens = metadata.prompt_tokens or kong.ctx.plugin.ai_stream_prompt_tokens
          end
        end

        framebuffer:put("data: ")
        framebuffer:put(formatted or "")
        framebuffer:put((formatted ~= "[DONE]") and "\n\n" or "")
      end
    end
  end

  local response_frame = framebuffer:get()
  framebuffer = nil
  if (not finished) and (is_gzip) then
    response_frame = kong_utils.deflate_gzip(response_frame)
  end

  ngx.arg[1] = response_frame

  if finished then
    local fake_response_t = {
      response = kong.ctx.plugin.ai_stream_log_buffer:get(),
      usage = {
        prompt_tokens = kong.ctx.plugin.ai_stream_prompt_tokens or 0,
        completion_tokens = kong.ctx.plugin.ai_stream_completion_tokens or 0,
        total_tokens = (kong.ctx.plugin.ai_stream_prompt_tokens or 0)
                     + (kong.ctx.plugin.ai_stream_completion_tokens or 0),
      }
    }

    ngx.arg[1] = nil
    ai_shared.post_request(conf, fake_response_t)
    kong.ctx.plugin.ai_stream_log_buffer = nil
  end
end

function _M:header_filter(conf)
  if kong.ctx.shared.skip_response_transformer then
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
  if kong.ctx.shared.ai_proxy_streaming_mode then
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
  if not kong.ctx.shared.ai_proxy_streaming_mode then
    local is_gzip = kong.response.get_header("Content-Encoding") == "gzip"
    if is_gzip then
      response_body = kong_utils.inflate_gzip(response_body)
    end

    local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
    if err then
      kong.ctx.plugin.ai_parser_error = true

      ngx.status = 500
      ERROR_MSG.error.message = err

      kong.ctx.plugin.parsed_response = cjson.encode(ERROR_MSG)

    elseif new_response_string then
      -- preserve the same response content type; assume the from_format function
      -- has returned the body in the appropriate response output format
      kong.ctx.plugin.parsed_response = new_response_string
    end
  end

  ai_driver.post_request(conf)
end


function _M:body_filter(conf)
  -- if body_filter is called twice, then return
  if kong.ctx.plugin.body_called and (not kong.ctx.shared.ai_proxy_streaming_mode) then
    return
  end

  if kong.ctx.shared.skip_response_transformer then
    local response_body
    if kong.ctx.shared.parsed_response then
      response_body = kong.ctx.shared.parsed_response
    elseif kong.response.get_status() == 200 then
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
    end

    local ai_driver = require("kong.llm.drivers." .. conf.model.provider)
    local route_type = conf.route_type
    local new_response_string, err = ai_driver.from_format(response_body, conf.model, route_type)
    
    if err then
      kong.log.warn("issue when transforming the response body for analytics in the body filter phase, ", err)
    elseif new_response_string then
      ai_shared.post_request(conf, new_response_string)
    end
  end

  if not kong.ctx.shared.skip_response_transformer then
    if (kong.response.get_status() ~= 200) and (not kong.ctx.plugin.ai_parser_error) then
      return
    end

    if kong.ctx.shared.ai_proxy_streaming_mode then
      handle_streaming_frame(conf)
    else
      -- all errors MUST be checked and returned in header_filter
      -- we should receive a replacement response body from the same thread

      local original_request = kong.ctx.plugin.parsed_response
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
  kong.ctx.plugin.body_called = true
end


function _M:access(conf)
  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type
  kong.ctx.plugin.operation = route_type

  local request_table

  -- we may have received a replacement / decorated request body from another AI plugin
  if kong.ctx.shared.replacement_request then
    kong.log.debug("replacement request body received from another AI plugin")
    request_table = kong.ctx.shared.replacement_request

  else
    -- first, calculate the coordinates of the request
    local content_type = kong.request.get_header("Content-Type") or "application/json"

    request_table = kong.request.get_body(content_type)

    -- TODO octet stream check here

    if not request_table then
      return bad_request("content-type header does not match request body")
    end
  end

  -- check the incoming format is the same as the configured LLM format
  local compatible, err = llm.is_compatible(request_table, route_type)
  if not compatible then
    kong.ctx.shared.skip_response_transformer = true
    return bad_request(err)
  end

  -- check if the user has asked for a stream, and/or if
  -- we are forcing all requests to be of streaming type
  if request_table.stream or
     (conf.model.options and conf.model.options.response_streaming) == "always" then
    -- this condition will only check if user has tried
    -- to activate streaming mode within their request
    if conf.model.options and conf.model.options.response_streaming == "deny" then
      return bad_request("response streaming is not enabled for this LLM")
    end

    -- store token cost estimate, on first pass
    if not kong.ctx.plugin.ai_stream_prompt_tokens then
      local prompt_tokens, err = ai_shared.calculate_cost(request_table or {}, {}, 1.8)
      if err then
        return internal_server_error("unable to estimate request token cost: " .. err)
      end

      kong.ctx.plugin.ai_stream_prompt_tokens = prompt_tokens
    end

    -- specific actions need to skip later for this to work
    kong.ctx.shared.ai_proxy_streaming_mode = true

  else
    kong.service.request.enable_buffering()
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- execute pre-request hooks for this driver
  local ok, err = ai_driver.pre_request(conf, request_table)
  if not ok then
    return bad_request(err)
  end

  -- transform the body to Kong-format for this provider/model
  local parsed_request_body, content_type, err = ai_driver.to_format(request_table, conf.model, route_type)
  if err then
    return bad_request(err)
  end

  -- execute pre-request hooks for "all" drivers before set new body
  local ok, err = ai_shared.pre_request(conf, parsed_request_body)
  if not ok then
    return bad_request(err)
  end

  kong.service.request.set_body(parsed_request_body, content_type)

  -- now re-configure the request for this operation type
  local ok, err = ai_driver.configure_request(conf)
  if not ok then
    return internal_server_error(err)
  end

  -- lights out, and away we go

end


return _M
