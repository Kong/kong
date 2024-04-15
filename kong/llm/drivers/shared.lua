local _M = {}

-- imports
local cjson     = require("cjson.safe")
local http      = require("resty.http")
local fmt       = string.format
local os        = os
local parse_url = require("socket.url").parse
--

local log_entry_keys = {
  REQUEST_BODY = "ai.payload.request",
  RESPONSE_BODY = "payload.response",

  TOKENS_CONTAINER = "usage",
  META_CONTAINER = "meta",

  -- meta keys
  REQUEST_MODEL = "request_model",
  RESPONSE_MODEL = "response_model",
  PROVIDER_NAME = "provider_name",
  PLUGIN_ID = "plugin_id",

  -- usage keys
  PROCESSING_TIME = "processing_time",
  PROMPT_TOKEN = "prompt_token",
  COMPLETION_TOKEN = "completion_token",
  TOTAL_TOKENS = "total_tokens",
}

local openai_override = os.getenv("OPENAI_TEST_PORT")

_M.streaming_has_token_counts = {
  ["cohere"] = true,
  ["llama2"] = true,
}

--- Splits a table key into nested tables.
-- Each part of the key separated by dots represents a nested table.
-- @param obj The table to split keys for.
-- @return A nested table structure representing the split keys.
local function split_table_key(obj)
  local result = {}

  for key, value in pairs(obj) do
    local keys = {}
    for k in key:gmatch("[^.]+") do
      table.insert(keys, k)
    end

    local currentTable = result
    for i, k in ipairs(keys) do
      if i < #keys then
        currentTable[k] = currentTable[k] or {}
        currentTable = currentTable[k]
      else
        currentTable[k] = value
      end
    end
  end

  return result
end

_M.upstream_url_format = {
  openai = fmt("%s://api.openai.com:%s", (openai_override and "http") or "https", (openai_override) or "443"),
  anthropic = "https://api.anthropic.com:443",
  cohere = "https://api.cohere.com:443",
  azure = "https://%s.openai.azure.com:443/openai/deployments/%s",
}

_M.operation_map = {
  openai = {
    ["llm/v1/completions"] = {
      path = "/v1/completions",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/chat/completions",
      method = "POST",
    },
  },
  anthropic = {
    ["llm/v1/completions"] = {
      path = "/v1/complete",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/messages",
      method = "POST",
    },
  },
  cohere = {
    ["llm/v1/completions"] = {
      path = "/v1/generate",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/v1/chat",
      method = "POST",
    },
  },
  azure = {
    ["llm/v1/completions"] = {
      path = "/completions",
      method = "POST",
    },
    ["llm/v1/chat"] = {
      path = "/chat/completions",
      method = "POST",
    },
  },
}

_M.clear_response_headers = {
  shared = {
    "Content-Length",
  },
  openai = {
    "Set-Cookie",
  },
  azure = {
    "Set-Cookie",
  },
  mistral = {
    "Set-Cookie",
  },
}


local function handle_stream_event(event_table, model_info, route_type)
  if event_table.done then
    -- return analytics table
    return nil, nil, {
      prompt_tokens = event_table.prompt_eval_count or 0,
      completion_tokens = event_table.eval_count or 0,
    }

  else
    -- parse standard response frame
    if route_type == "stream/llm/v1/chat" then
      return {
        choices = {
          [1] = {
            delta = {
              content = event_table.message and event_table.message.content or "",
            },
            index = 0,
          },
        },
        model = event_table.model,
        object = "chat.completion.chunk",
      }

    elseif route_type == "stream/llm/v1/completions" then
      return {
        choices = {
          [1] = {
            text = event_table.response or "",
            index = 0,
          },
        },
        model = event_table.model,
        object = "text_completion",
      }

    end
  end
end


function _M.to_ollama(request_table, model)
  local input = {}

  if request_table.prompt and request_table.messages then
    return kong.response.exit(400, "cannot run raw 'prompt' and chat history 'messages' requests at the same time - refer to schema")

  elseif request_table.messages then
    input.messages = request_table.messages

  elseif request_table.prompt then
    input.prompt = request_table.prompt

  end

  -- common parameters
  input.stream = request_table.stream or false -- for future capability
  input.model = model.name

  if model.options then
    input.options = {}

    if model.options.max_tokens then input.options.num_predict = model.options.max_tokens end
    if model.options.temperature then input.options.temperature = model.options.temperature end
    if model.options.top_p then input.options.top_p = model.options.top_p end
    if model.options.top_k then input.options.top_k = model.options.top_k end
  end

  return input, "application/json", nil
end

function _M.from_ollama(response_string, model_info, route_type)
  local output, _, analytics

  local response_table, err = cjson.decode(response_string)
  if err then
    return nil, "failed to decode ollama response"
  end

  if route_type == "stream/llm/v1/chat" then
    output, _, analytics = handle_stream_event(response_table, model_info, route_type)

  elseif route_type == "stream/llm/v1/completions" then
    output, _, analytics = handle_stream_event(response_table, model_info, route_type)

  else
    -- there is no direct field indicating STOP reason, so calculate it manually
    local stop_length = (model_info.options and model_info.options.max_tokens) or -1
    local stop_reason = "stop"
    if response_table.eval_count and response_table.eval_count == stop_length then
      stop_reason = "length"
    end

    output = {}

    -- common fields
    output.model = response_table.model
    output.created = response_table.created_at

    -- analytics
    output.usage = {
      completion_tokens = response_table.eval_count or 0,
      prompt_tokens = response_table.prompt_eval_count or 0,
      total_tokens = (response_table.eval_count or 0) + 
                    (response_table.prompt_eval_count or 0),
    }

    if route_type == "llm/v1/chat" then
      output.object = "chat.completion"
      output.choices = {
        {
          finish_reason = stop_reason,
          index = 0,
          message = response_table.message,
        }
      }

    elseif route_type == "llm/v1/completions" then
      output.object = "text_completion"
      output.choices = {
        {
          index = 0,
          text = response_table.response,
        }
      }

    else
      return nil, "no ollama-format transformer for response type " .. route_type

    end
  end

  return output and cjson.encode(output) or nil, nil, analytics
end

function _M.pre_request(conf, request_table)
  -- process form/json body auth information
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location
  
  if auth_param_name and auth_param_value and auth_param_location == "body" then
    request_table[auth_param_name] = auth_param_value
  end

  -- if enabled AND request type is compatible, capture the input for analytics
  if conf.logging and conf.logging.log_payloads then
    kong.log.set_serialize_value(log_entry_keys.REQUEST_BODY, kong.request.get_raw_body())
  end

  return true, nil
end

function _M.post_request(conf, response_object)
  local body_string, err

  if type(response_object) == "string" then
    -- set raw string body first, then decode
    body_string = response_object

    -- unpack the original response object for getting token and meta info
    response_object, err = cjson.decode(response_object)
    if err then
      return nil, "failed to decode LLM response from JSON"
    end
  else
    -- this has come from another AI subsystem, is already formatted, and contains "response" field
    body_string = response_object.response or "ERROR__NOT_SET"
  end

  -- analytics and logging
  if conf.logging and conf.logging.log_statistics then
    local provider_name = conf.model.provider

    -- check if we already have analytics in this context
    local request_analytics = kong.ctx.shared.analytics

    -- create a new try context
    local current_try = {
      [log_entry_keys.META_CONTAINER] = {},
      [log_entry_keys.TOKENS_CONTAINER] = {},
    }

    -- create a new structure if not
    if not request_analytics then
      request_analytics = {}
    end

    -- check if we already have analytics for this provider
    local request_analytics_provider = request_analytics[provider_name]

    -- create a new structure if not
    if not request_analytics_provider then
      request_analytics_provider = {
        request_prompt_tokens = 0,
        request_completion_tokens = 0,
        request_total_tokens = 0,
        number_of_instances = 0,
        instances = {},
      }
    end

    -- Set the model, response, and provider names in the current try context
    current_try[log_entry_keys.META_CONTAINER][log_entry_keys.REQUEST_MODEL] = conf.model.name
    current_try[log_entry_keys.META_CONTAINER][log_entry_keys.RESPONSE_MODEL] = response_object.model or conf.model.name
    current_try[log_entry_keys.META_CONTAINER][log_entry_keys.PROVIDER_NAME] = provider_name
    current_try[log_entry_keys.META_CONTAINER][log_entry_keys.PLUGIN_ID] = conf.__plugin_id

    -- Capture openai-format usage stats from the transformed response body
    if response_object.usage then
      if response_object.usage.prompt_tokens then
        request_analytics_provider.request_prompt_tokens = (request_analytics_provider.request_prompt_tokens + response_object.usage.prompt_tokens)
        current_try[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.PROMPT_TOKEN] = response_object.usage.prompt_tokens
      end
      if response_object.usage.completion_tokens then
        request_analytics_provider.request_completion_tokens = (request_analytics_provider.request_completion_tokens + response_object.usage.completion_tokens)
        current_try[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.COMPLETION_TOKEN] = response_object.usage.completion_tokens
      end
      if response_object.usage.total_tokens then
        request_analytics_provider.request_total_tokens = (request_analytics_provider.request_total_tokens + response_object.usage.total_tokens)
        current_try[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.TOTAL_TOKENS] = response_object.usage.total_tokens
      end
    end

    -- Log response body if logging payloads is enabled
    if conf.logging and conf.logging.log_payloads then
      current_try[log_entry_keys.RESPONSE_BODY] = body_string
    end

    -- Increment the number of instances
    request_analytics_provider.number_of_instances = request_analytics_provider.number_of_instances + 1

    -- Get the current try count
    local try_count = request_analytics_provider.number_of_instances

    -- Store the split key data in instances
    request_analytics_provider.instances[try_count] = split_table_key(current_try)

    -- Update context with changed values
    request_analytics[provider_name] = request_analytics_provider
    kong.ctx.shared.analytics = request_analytics

    -- Log analytics data
    kong.log.set_serialize_value(fmt("%s.%s", "ai", provider_name), request_analytics_provider)
  end

  return nil
end

function _M.http_request(url, body, method, headers, http_opts, buffered)
  local httpc = http.new()

  if http_opts.http_timeout then
    httpc:set_timeouts(http_opts.http_timeout)
  end

  if http_opts.proxy_opts then
    httpc:set_proxy_options(http_opts.proxy_opts)
  end

  local parsed = parse_url(url)

  if buffered then
    local ok, err, _ = httpc:connect({
      scheme = parsed.scheme,
      host = parsed.host,
      port = parsed.port or 443,  -- this always fails. experience.
      ssl_server_name = parsed.host,
      ssl_verify = http_opts.https_verify,
    })
    if not ok then
      return nil, err
    end

    local res, err = httpc:request({
        path = parsed.path or "/",
        query = parsed.query,
        method = method,
        headers = headers,
        body = body,
    })
    if not res then
      return nil, "connection failed: " .. err
    end

    return res, nil, httpc
  else
    -- 'single-shot'
    local res, err = httpc:request_uri(
      url,
      {
        method = method,
        body = body,
        headers = headers,
        ssl_verify = http_opts.https_verify,
      })
    if not res then
      return nil, "request failed: " .. err
    end

    return res, nil, nil
  end
end

return _M
