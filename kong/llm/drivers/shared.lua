local _M = {}

-- imports
local cjson     = require("cjson.safe")
local http      = require("resty.http")
local fmt       = string.format
local os        = os
local parse_url = require("socket.url").parse
--

-- static
local str_find   = string.find
local str_sub    = string.sub
local tbl_insert = table.insert

local function str_ltrim(s) -- remove leading whitespace from string.
  return (s:gsub("^%s*", ""))
end
--

local log_entry_keys = {
  TOKENS_CONTAINER = "usage",
  META_CONTAINER = "meta",
  PAYLOAD_CONTAINER = "payload",
  REQUEST_BODY = "ai.payload.request",

  -- payload keys
  RESPONSE_BODY = "response",

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
    return "[DONE]", nil, {
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

local function complex_split(str, delimiter)
  local result = {}
  local from  = 1
  local delim_from, delim_to = string.find(str, delimiter, from)
  while delim_from do
    table.insert( result, string.sub(str, from , delim_from-1))
    from  = delim_to + 1
    delim_from, delim_to = string.find(str, delimiter, from)
  end
  table.insert( result, string.sub(str, from))
  return result
end

function _M.frame_to_events(frame)
  local events = {}

  -- todo check if it's raw json and
  -- just return the split up data frame
  if string.sub(str_ltrim(frame), 1, 1) == "{" then
    for event in frame:gmatch("[^\r\n]+") do
      events[#events + 1] = {
        data = event,
      }
    end
  else
    local event_lines = complex_split(frame, "\n")
    local struct = { event = nil, id = nil, data = nil }

    for _, dat in ipairs(event_lines) do
      if #dat < 1 then
        events[#events + 1] = struct
        struct = { event = nil, id = nil, data = nil }
      end

      local s1, _ = str_find(dat, ":") -- find where the cut point is

      if s1 and s1 ~= 1 then
        local field = str_sub(dat, 1, s1-1) -- returns "data " from data: hello world
        local value = str_ltrim(str_sub(dat, s1+1)) -- returns "hello world" from data: hello world

        -- for now not checking if the value is already been set
        if     field == "event" then struct.event = value
        elseif field == "id"    then struct.id = value
        elseif field == "data"  then struct.data = value
        end -- if
      end -- if
    end
  end
  
  return events
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
  
  if output and output ~= "[DONE]" then
    output, err = cjson.encode(output)
  end

  -- err maybe be nil from successful decode above
  return output, err, analytics
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

    local plugin_name = conf.__key__:match('plugins:(.-):')
    if not plugin_name or plugin_name == "" then
      return nil, "no plugin name is being passed by the plugin"
    end

    -- check if we already have analytics in this context
    local request_analytics = kong.ctx.shared.analytics

    -- create a new structure if not
    if not request_analytics then
      request_analytics = {}
    end

    -- check if we already have analytics for this provider
    local request_analytics_plugin = request_analytics[plugin_name]

    -- create a new structure if not
    if not request_analytics_plugin then
      request_analytics_plugin = {
        [log_entry_keys.META_CONTAINER] = {},
        [log_entry_keys.PAYLOAD_CONTAINER] = {},
        [log_entry_keys.TOKENS_CONTAINER] = {
          [log_entry_keys.PROMPT_TOKEN] = 0,
          [log_entry_keys.COMPLETION_TOKEN] = 0,
          [log_entry_keys.TOTAL_TOKENS] = 0,
        },
      }
    end

    -- Set the model, response, and provider names in the current try context
    request_analytics_plugin[log_entry_keys.META_CONTAINER][log_entry_keys.REQUEST_MODEL] = conf.model.name
    request_analytics_plugin[log_entry_keys.META_CONTAINER][log_entry_keys.RESPONSE_MODEL] = response_object.model or conf.model.name
    request_analytics_plugin[log_entry_keys.META_CONTAINER][log_entry_keys.PROVIDER_NAME] = provider_name
    request_analytics_plugin[log_entry_keys.META_CONTAINER][log_entry_keys.PLUGIN_ID] = conf.__plugin_id

    -- Capture openai-format usage stats from the transformed response body
    if response_object.usage then
      if response_object.usage.prompt_tokens then
        request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.PROMPT_TOKEN] = request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.PROMPT_TOKEN] + response_object.usage.prompt_tokens
      end
      if response_object.usage.completion_tokens then
        request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.COMPLETION_TOKEN] = request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.COMPLETION_TOKEN] + response_object.usage.completion_tokens
      end
      if response_object.usage.total_tokens then
        request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.TOTAL_TOKENS] = request_analytics_plugin[log_entry_keys.TOKENS_CONTAINER][log_entry_keys.TOTAL_TOKENS] + response_object.usage.total_tokens
      end
    end

    -- Log response body if logging payloads is enabled
    if conf.logging and conf.logging.log_payloads then
      request_analytics_plugin[log_entry_keys.PAYLOAD_CONTAINER][log_entry_keys.RESPONSE_BODY] = body_string
    end

    -- Update context with changed values
    request_analytics[plugin_name] = request_analytics_plugin
    kong.ctx.shared.analytics = request_analytics

    -- Log analytics data
    kong.log.set_serialize_value(fmt("%s.%s", "ai", plugin_name), request_analytics_plugin)
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

-- Function to count the number of words in a string
local function count_words(str)
  local count = 0
  for word in str:gmatch("%S+") do
      count = count + 1
  end
  return count
end

-- Function to count the number of words or tokens based on the content type
local function count_prompt(content, tokens_factor)
  local count = 0

  if type(content) == "string" then
    count = count_words(content) * tokens_factor
  elseif type(content) == "table" then
    for _, item in ipairs(content) do
      if type(item) == "string" then
        count = count + (count_words(item) * tokens_factor)
      elseif type(item) == "number" then
        count = count + 1
      elseif type(item) == "table" then
        for _2, item2 in ipairs(item) do
          if type(item2) == "number" then
            count = count + 1
          else
            return nil, "Invalid request format"
          end
        end
      else
          return nil, "Invalid request format"
      end
    end
  else 
    return nil, "Invalid request format"
  end
  return count
end

function _M.calculate_cost(query_body, tokens_models, tokens_factor)
  local query_cost = 0
  local err

  if query_body.messages then
    -- Calculate the cost based on the content type
    for _, message in ipairs(query_body.messages) do
        query_cost = query_cost + (count_words(message.content) * tokens_factor)
    end
  elseif query_body.prompt then
    -- Calculate the cost based on the content type
    query_cost, err = count_prompt(query_body.prompt, tokens_factor)
    if err then
        return nil, err
    end
  else
    return nil, "No messages or prompt in query"
  end

  -- Round the total cost quantified
  query_cost = math.floor(query_cost + 0.5)

  return query_cost
end

return _M
