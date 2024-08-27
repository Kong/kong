local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require("socket.url")
local string_gsub = string.gsub
local table_insert = table.insert
local string_lower = string.lower
local signer = require("resty.aws.request.sign")
local llm_state = require("kong.llm.state")
--

-- globals
local DRIVER_NAME = "bedrock"
--

local _OPENAI_ROLE_MAPPING = {
  ["system"] = "assistant",
  ["user"] = "user",
  ["assistant"] = "assistant",
}

_M.bedrock_unsupported_system_role_patterns = {
  "amazon.titan.-.*",
  "cohere.command.-text.-.*",
  "cohere.command.-light.-text.-.*",
  "mistral.mistral.-7b.-instruct.-.*",
  "mistral.mixtral.-8x7b.-instruct.-.*",
}

local function to_bedrock_generation_config(request_table)
  return {
    ["maxTokens"] = request_table.max_tokens,
    ["stopSequences"] = request_table.stop,
    ["temperature"] = request_table.temperature,
    ["topP"] = request_table.top_p,
  }
end

local function to_additional_request_fields(request_table)
  return {
    request_table.bedrock.additionalModelRequestFields
  }
end

local function to_tool_config(request_table)
  return {
    request_table.bedrock.toolConfig
  }
end

local function handle_stream_event(event_t, model_info, route_type)
  local new_event, metadata

  if (not event_t) or (not event_t.data) then
    return "", nil, nil
  end

  -- decode and determine the event type
  local event = cjson.decode(event_t.data)  
  local event_type = event and event.headers and event.headers[":event-type"]

  if not event_type then
    return "", nil, nil
  end

  local body = event.body and cjson.decode(event.body)

  if not body then
    return "", nil, nil
  end

  if event_type == "messageStart" then
    new_event = {
      choices = {
        [1] = {
          delta = {
            content = "",
            role = body.role,
          },
          index = 0,
          logprobs = cjson.null,
        },
      },
      model = model_info.name,
      object = "chat.completion.chunk",
      system_fingerprint = cjson.null,
    }

  elseif event_type == "contentBlockDelta" then
    new_event = {
      choices = {
        [1] = {
          delta = {
            content = (body.delta
                   and body.delta.text)
                   or "",
          },
          index = 0,
          finish_reason = cjson.null,
          logprobs = cjson.null,
        },
      },
      model = model_info.name,
      object = "chat.completion.chunk",
    }

  elseif event_type == "messageStop" then
    new_event = {
      choices = {
        [1] = {
          delta = {},
          index = 0,
          finish_reason = body.stopReason,
          logprobs = cjson.null,
        },
      },
      model = model_info.name,
      object = "chat.completion.chunk",
    }

  elseif event_type == "metadata" then
    metadata = {
      prompt_tokens = body.usage and body.usage.inputTokens or 0,
      completion_tokens = body.usage and body.usage.outputTokens or 0,
    }

    new_event = ai_shared._CONST.SSE_TERMINATOR

  -- "contentBlockStop" is absent because it is not used for anything here
  end

  if new_event then
    if new_event ~= ai_shared._CONST.SSE_TERMINATOR then
      new_event = cjson.encode(new_event)
    end

    return new_event, nil, metadata
  else
    return nil, nil, metadata  -- caller code will handle "unrecognised" event types
  end
end

local function to_bedrock_chat_openai(request_table, model_info, route_type)
  if not request_table then  -- try-catch type mechanism
    local err = "empty request table received for transformation"
    ngx.log(ngx.ERR, "[bedrock] ", err)
    return nil, nil, err
  end

  local new_r = {}

  -- anthropic models support variable versions, just like self-hosted
  new_r.anthropic_version = model_info.options and model_info.options.anthropic_version
                         or "bedrock-2023-05-31"

  if request_table.messages and #request_table.messages > 0 then
    local system_prompts = {}

    for i, v in ipairs(request_table.messages) do
      -- for 'system', we just concat them all into one Bedrock instruction
      if v.role and v.role == "system" then
        system_prompts[#system_prompts+1] = { text = v.content }

      else
        local content
        if type(v.content) == "table" then
          content = v.content
        else
          content = {
            {
              text = v.content or ""
            },
          }
        end

        -- for any other role, just construct the chat history as 'parts.text' type
        new_r.messages = new_r.messages or {}
        table_insert(new_r.messages, {
          role = _OPENAI_ROLE_MAPPING[v.role or "user"],  -- default to 'user'
          content = content,
        })
      end
    end

    -- only works for some models
    if #system_prompts > 0 then
      for _, p in ipairs(_M.bedrock_unsupported_system_role_patterns) do
        if model_info.name:find(p) then
          return nil, nil, "system prompts are unsupported for model '" .. model_info.name
        end
      end

      new_r.system = system_prompts
    end
  end

  new_r.inferenceConfig = to_bedrock_generation_config(request_table)

  new_r.toolConfig = request_table.bedrock
                 and request_table.bedrock.toolConfig
                 and to_tool_config(request_table)

  new_r.additionalModelRequestFields = request_table.bedrock
                                   and request_table.bedrock.additionalModelRequestFields
                                   and to_additional_request_fields(request_table)

  return new_r, "application/json", nil
end

local function from_bedrock_chat_openai(response, model_info, route_type)
  local response, err = cjson.decode(response)

  if err then
    local err_client = "failed to decode response from Bedrock"
    ngx.log(ngx.ERR, fmt("[bedrock] %s: %s", err_client, err))
    return nil, err_client
  end

  -- messages/choices table is only 1 size, so don't need to static allocate
  local client_response = {}
  client_response.choices = {}

  if response.output
        and response.output.message
        and response.output.message.content
        and #response.output.message.content > 0
        and response.output.message.content[1].text then

          client_response.choices[1] = {
      index = 0,
      message = {
        role = "assistant",
        content = response.output.message.content[1].text,
      },
      finish_reason = string_lower(response.stopReason),
    }
    client_response.object = "chat.completion"
    client_response.model = model_info.name

  else -- probably a server fault or other unexpected response
    local err = "no generation candidates received from Bedrock, or max_tokens too short"
    ngx.log(ngx.ERR, "[bedrock] ", err)
    return nil, err
  end

  -- process analytics
  if response.usage then
    client_response.usage = {
      prompt_tokens = response.usage.inputTokens,
      completion_tokens = response.usage.outputTokens,
      total_tokens = response.usage.totalTokens,
    }
  end

  return cjson.encode(client_response)
end

local transformers_to = {
  ["llm/v1/chat"] = to_bedrock_chat_openai,
}

local transformers_from = {
  ["llm/v1/chat"] = from_bedrock_chat_openai,
  ["stream/llm/v1/chat"] = handle_stream_event,
}

function _M.from_format(response_string, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  -- MUST return a string, to set as the response body
  if not transformers_from[route_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end

  local ok, response_string, err, metadata = pcall(transformers_from[route_type], response_string, model_info, route_type)
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

  if not transformers_to[route_type] then
    return nil, nil, fmt("no transformer for %s://%s", model_info.provider, route_type)
  end

  request_table = ai_shared.merge_config_defaults(request_table, model_info.options, model_info.route_type)

  local ok, response_object, content_type, err = pcall(
    transformers_to[route_type],
    request_table,
    model_info
  )
  if err or (not ok) then
    return nil, nil, fmt("error transforming to %s://%s: %s", model_info.provider, route_type, err)
  end

  return response_object, content_type, nil
end

function _M.subrequest(body, conf, http_opts, return_res_table, identity_interface)
  -- use shared/standard subrequest routine
  local body_string, err

  if type(body) == "table" then
    body_string, err = cjson.encode(body)
    if err then
      return nil, nil, "failed to parse body to json: " .. err
    end
  elseif type(body) == "string" then
    body_string = body
  else
    return nil, nil, "body must be table or string"
  end

  -- may be overridden
  local f_url = conf.model.options and conf.model.options.upstream_url
  if not f_url then  -- upstream_url override is not set
    local uri = fmt(ai_shared.upstream_url_format[DRIVER_NAME], identity_interface.interface.config.region)
    local path = fmt(
      ai_shared.operation_map[DRIVER_NAME][conf.route_type].path,
      conf.model.name,
      "converse")

    f_url = uri ..path
  end

  local parsed_url = socket_url.parse(f_url)
  local method = ai_shared.operation_map[DRIVER_NAME][conf.route_type].method

  -- do the IAM auth and signature headers
  identity_interface.interface.config.signatureVersion = "v4"
  identity_interface.interface.config.endpointPrefix = "bedrock"

  local r = {
    headers = {},
    method = method,
    path = parsed_url.path,
    host = parsed_url.host,
    port = tonumber(parsed_url.port) or 443,
    body = body_string,
  }

  local signature, err = signer(identity_interface.interface.config, r)
  if not signature then
    return nil, "failed to sign AWS request: " .. (err or "NONE")
  end

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
  }
  headers["Authorization"] = signature.headers["Authorization"]
  if signature.headers["X-Amz-Security-Token"] then 
    headers["X-Amz-Security-Token"] = signature.headers["X-Amz-Security-Token"]
  end
  if signature.headers["X-Amz-Date"] then
    headers["X-Amz-Date"] = signature.headers["X-Amz-Date"]
  end

  local res, err, httpc = ai_shared.http_request(f_url, body_string, method, headers, http_opts, return_res_table)
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
  -- force gzip for bedrock because brotli and others break streaming
  kong.service.request.set_header("Accept-Encoding", "gzip, identity")

  return true, nil
end

-- returns err or nil
function _M.configure_request(conf, aws_sdk)
  local operation = llm_state.is_streaming_mode() and "converse-stream"
                                                             or "converse"

  local f_url = conf.model.options and conf.model.options.upstream_url
  if not f_url then  -- upstream_url override is not set
    local uri = fmt(ai_shared.upstream_url_format[DRIVER_NAME], aws_sdk.config.region)
    local path = fmt(
      ai_shared.operation_map[DRIVER_NAME][conf.route_type].path,
      conf.model.name,
      operation)

    f_url = uri ..path
  end

  local parsed_url = socket_url.parse(f_url)

  if conf.model.options and conf.model.options.upstream_path then
    -- upstream path override is set (or templated from request params)
    parsed_url.path = conf.model.options.upstream_path
  end

  -- if the path is read from a URL capture, ensure that it is valid
  parsed_url.path = string_gsub(parsed_url.path, "^/*", "/")

  ai_shared.override_upstream_url(parsed_url, conf)

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, (tonumber(parsed_url.port) or 443))

  -- do the IAM auth and signature headers
  aws_sdk.config.signatureVersion = "v4"
  aws_sdk.config.endpointPrefix = "bedrock"

  local r = {
    headers = {},
    method = ai_shared.operation_map[DRIVER_NAME][conf.route_type].method,
    path = parsed_url.path,
    host = parsed_url.host,
    port = tonumber(parsed_url.port) or 443,
    body = kong.request.get_raw_body()
  }

  local signature, err = signer(aws_sdk.config, r)
  if not signature then
    return nil, "failed to sign AWS request: " .. (err or "NONE")
  end

  kong.service.request.set_header("Authorization", signature.headers["Authorization"])
  if signature.headers["X-Amz-Security-Token"] then 
    kong.service.request.set_header("X-Amz-Security-Token", signature.headers["X-Amz-Security-Token"])
  end
  if signature.headers["X-Amz-Date"] then
    kong.service.request.set_header("X-Amz-Date", signature.headers["X-Amz-Date"])
  end

  return true
end

return _M
