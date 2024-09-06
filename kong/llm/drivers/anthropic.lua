local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require "socket.url"
local buffer = require("string.buffer")
local string_gsub = string.gsub
--

-- globals
local DRIVER_NAME = "anthropic"
--

local function kong_prompt_to_claude_prompt(prompt)
  return fmt("Human: %s\n\nAssistant:", prompt)
end

local function kong_messages_to_claude_prompt(messages)
  local buf = buffer.new()

  -- We need to flatten the messages into an assistant chat history for Claude
  for _, v in ipairs(messages) do
    if v.role == "assistant" then
      buf:put("Assistant: ")

    elseif v.role == "user" then
      buf:put("Human: ")

    end
    -- 'system' prompts don't have a role, and just start text streaming from the top
    -- https://docs.anthropic.com/claude/docs/how-to-use-system-prompts

    buf:put(v.content)
    buf:put("\n\n")
  end

  -- claude 2.x requests always end with an open prompt,
  -- telling the Assistant you are READY for its answer.
  -- https://docs.anthropic.com/claude/docs/introduction-to-prompt-design
  buf:put("Assistant:")

  return buf:get()
end

-- reuse the messages structure of prompt
-- extract messages and system from kong request
local function kong_messages_to_claude_messages(messages)
  local msgs, system, n = {}, nil, 1

  for _, v in ipairs(messages) do
    if v.role ~= "assistant" and v.role ~= "user" then
      system = v.content

    else
      msgs[n] = v
      n = n + 1
    end
  end

  return msgs, system
end


local function to_claude_prompt(req)
  if req.prompt then
    return kong_prompt_to_claude_prompt(req.prompt)

  elseif req.messages then
    return kong_messages_to_claude_prompt(req.messages)

  end

  return nil, "request is missing .prompt and .messages commands"
end

local function to_claude_messages(req)
  if req.messages then
    return kong_messages_to_claude_messages(req.messages)
  end

  return nil, nil, "request is missing .messages command"
end

local transformers_to = {
  ["llm/v1/chat"] = function(request_table, model)
    local messages = {}
    local err

    messages.messages, messages.system, err = to_claude_messages(request_table)
    if err then
      return nil, nil, err
    end

    messages.temperature = (model.options and model.options.temperature) or request_table.temperature
    messages.max_tokens = (model.options and model.options.max_tokens) or request_table.max_tokens
    messages.model = model.name or request_table.model
    messages.stream = request_table.stream or false  -- explicitly set this if nil

    return messages, "application/json", nil
  end,

  ["llm/v1/completions"] = function(request_table, model)
    local prompt = {}
    local err

    prompt.prompt, err = to_claude_prompt(request_table)
    if err then
      return nil, nil, err
    end

    prompt.temperature = (model.options and model.options.temperature) or request_table.temperature
    prompt.max_tokens_to_sample = (model.options and model.options.max_tokens) or request_table.max_tokens
    prompt.model = model.name or request_table.model
    prompt.stream = request_table.stream or false  -- explicitly set this if nil

    return prompt, "application/json", nil
  end,
}

local function delta_to_event(delta, model_info)
  local data = {
    choices = {
      [1] = {
        delta = {
          content = (delta.delta
                 and delta.delta.text)
                 or (delta.content_block
                 and "")
                 or "",
        },
        index = 0,
        finish_reason = cjson.null,
        logprobs = cjson.null,
      },
    },
    id = kong
     and kong.ctx
     and kong.ctx.plugin
     and kong.ctx.plugin.ai_proxy_anthropic_stream_id,
    model = model_info.name,
    object = "chat.completion.chunk",
  }

  return cjson.encode(data), nil, nil
end

local function start_to_event(event_data, model_info)
  local meta = event_data.message or {}

  local metadata = {
    prompt_tokens = meta.usage
                    and meta.usage.input_tokens,
    completion_tokens = meta.usage
                    and meta.usage.output_tokens,
    model = meta.model,
    stop_reason = meta.stop_reason,
    stop_sequence = meta.stop_sequence,
  }

  local message = {
    choices = {
      [1] = {
        delta = {
          content = "",
          role = meta.role,
        },
        index = 0,
        logprobs = cjson.null,
      },
    },
    id = meta.id,
    model = model_info.name,
    object = "chat.completion.chunk",
    system_fingerprint = cjson.null,
  }

  message = cjson.encode(message)
  kong.ctx.plugin.ai_proxy_anthropic_stream_id = meta.id

  return message, nil, metadata
end

local function handle_stream_event(event_t, model_info, route_type)
  local event_id = event_t.event
  local event_data = cjson.decode(event_t.data)

  if not event_id or not event_data then
    return nil, "transformation to stream event failed or empty stream event received", nil
  end

  if event_id == "message_start" then
    -- message_start and contains the token usage and model metadata

    if event_data and event_data.message then
      return start_to_event(event_data, model_info)
    else
      return nil, "message_start is missing the metadata block", nil
    end

  elseif event_id == "message_delta" then
    -- message_delta contains and interim token count of the
    -- last few frames / iterations
    if event_data
    and event_data.usage then
      return nil, nil, {
        prompt_tokens = nil,
        completion_tokens = event_data.usage.output_tokens,
        stop_reason = event_data.delta
                  and event_data.delta.stop_reason,
        stop_sequence = event_data.delta
                    and event_data.delta.stop_sequence,
      }
    else
      return nil, "message_delta is missing the metadata block", nil
    end

  elseif event_id == "content_block_start" then
    -- content_block_start is just an empty string and indicates
    -- that we're getting an actual answer
    return delta_to_event(event_data, model_info)

  elseif event_id == "content_block_delta" then
    return delta_to_event(event_data, model_info)

  elseif event_id == "message_stop" then
    return ai_shared._CONST.SSE_TERMINATOR, nil, nil

  elseif event_id == "ping" then
    return nil, nil, nil

  end
end

local transformers_from = {
  ["llm/v1/chat"] = function(response_string)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode anthropic response"
    end

    local function extract_text_from_content(content)
      local buf = buffer.new()
      for i, v in ipairs(content) do
        if i ~= 1 then
          buf:put("\n")
        end

        buf:put(v.text)
      end

      return buf:tostring()
    end

    if response_table.content then
      local usage = response_table.usage

      if usage then
        usage = {
          prompt_tokens = usage.input_tokens,
          completion_tokens = usage.output_tokens,
          total_tokens = usage.input_tokens and usage.output_tokens and
            usage.input_tokens + usage.output_tokens,
        }

      else
        usage = "no usage data returned from upstream"
      end

      local res = {
        choices = {
          {
            index = 0,
            message = {
              role = "assistant",
              content = extract_text_from_content(response_table.content),
            },
            finish_reason = response_table.stop_reason,
          },
        },
        usage = usage,
        model = response_table.model,
        object = "chat.content",
      }

      return cjson.encode(res)
    else
      -- it's probably an error block, return generic error
      return nil, "'content' not in anthropic://llm/v1/chat response"
    end
  end,

  ["llm/v1/completions"] = function(response_string)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode anthropic response"
    end

    if response_table.completion then
      local res = {
        choices = {
          {
            index = 0,
            text = response_table.completion,
            finish_reason = response_table.stop_reason,
          },
        },
        model = response_table.model,
        object = "text_completion",
      }

      return cjson.encode(res)
    else
      -- it's probably an error block, return generic error
      return nil, "'completion' not in anthropic://llm/v1/chat response"
    end
  end,

  ["stream/llm/v1/chat"] = handle_stream_event,
}

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  local transform = transformers_from[route_type]
  if not transform then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end

  local ok, response_string, err, metadata = pcall(transform, response_string, model_info, route_type)
  if not ok or err then
    return nil, fmt("transformation failed from type %s://%s: %s",
                    model_info.provider,
                    route_type,
                    err or "unexpected_error"
                )
  end

  return response_string, nil, metadata
end

function _M.to_format(request_table, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from kong type to ", model_info.provider, "/", route_type)

  if route_type == "preserve" then
    -- do nothing
    return request_table, nil, nil
  end

  request_table = ai_shared.merge_config_defaults(request_table, model_info.options, model_info.route_type)

  if not transformers_to[route_type] then
    return nil, nil, fmt("no transformer for %s://%s", model_info.provider, route_type)
  end

  local ok, request_object, content_type, err = pcall(
    transformers_to[route_type],
    request_table,
    model_info
  )
  if err or (not ok) then
    return nil, nil, fmt("error transforming to %s://%s", model_info.provider, route_type)
  end

  return request_object, content_type, nil
end

function _M.subrequest(body, conf, http_opts, return_res_table)
  -- use shared/standard subrequest routine with custom header
  local body_string, err

  if type(body) == "table" then
    body_string, err = cjson.encode(body)
    if err then 
      return nil, nil, "failed to parse body to json: " .. err
    end
  elseif type(body) == "string" then
    body_string = body
  else
    error("body must be table or string")
  end

  -- may be overridden
  local url = (conf.model.options and conf.model.options.upstream_url)
    or fmt(
    "%s%s",
    ai_shared.upstream_url_format[DRIVER_NAME],
    ai_shared.operation_map[DRIVER_NAME][conf.route_type].path
  )

  local method = ai_shared.operation_map[DRIVER_NAME][conf.route_type].method

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
    ["anthropic-version"] = conf.model.options.anthropic_version,
  }

  if conf.auth and conf.auth.header_name then
    headers[conf.auth.header_name] = conf.auth.header_value
  end

  local res, err, httpc = ai_shared.http_request(url, body_string, method, headers, http_opts, return_res_table)
  if err then
    return nil, nil, "request to ai service failed: " .. err
  end

  if return_res_table then
    return res, res.status, nil, httpc
  else
    -- At this point, the entire request / response is complete and the connection
    -- will be closed or back on the connection pool.
    local status = res.status
    local body   = res.body

    if status > 299 then
      return body, res.status, "status code " .. status
    end

    return body, res.status, nil
  end
end

function _M.header_filter_hooks(body)
  -- nothing to parse in header_filter phase
end

function _M.post_request(conf)
  if ai_shared.clear_response_headers[DRIVER_NAME] then
    for i, v in ipairs(ai_shared.clear_response_headers[DRIVER_NAME]) do
      kong.response.clear_header(v)
    end
  end
end

function _M.pre_request(conf, body)
  return true
end

-- returns err or nil
function _M.configure_request(conf)
  local parsed_url

  if conf.model.options.upstream_url then
    parsed_url = socket_url.parse(conf.model.options.upstream_url)
  else
    parsed_url = socket_url.parse(ai_shared.upstream_url_format[DRIVER_NAME])
    parsed_url.path = (conf.model.options and
                        conf.model.options.upstream_path)
                      or (ai_shared.operation_map[DRIVER_NAME][conf.route_type] and
                        ai_shared.operation_map[DRIVER_NAME][conf.route_type].path)
                      or "/"
  end

  ai_shared.override_upstream_url(parsed_url, conf)

  -- if the path is read from a URL capture, ensure that it is valid
  parsed_url.path = string_gsub(parsed_url.path, "^/*", "/")

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, (tonumber(parsed_url.port) or 443))



  kong.service.request.set_header("anthropic-version", conf.model.options.anthropic_version)

  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  if auth_header_name and auth_header_value then
    local exist_value = kong.request.get_header(auth_header_name)
    if exist_value == nil or not conf.auth.allow_override then
      kong.service.request.set_header(auth_header_name, auth_header_value)
    end
  end

  if auth_param_name and auth_param_value and auth_param_location == "query" then
    local query_table = kong.request.get_query()
    if query_table[auth_param_name] == nil or not conf.auth.allow_override then
      query_table[auth_param_name] = auth_param_value
      kong.service.request.set_query(query_table)
    end
  end

  -- if auth_param_location is "form", it will have already been set in a pre-request hook
  return true, nil
end


return _M
