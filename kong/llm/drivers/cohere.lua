local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require "socket.url"
local table_new = require("table.new")
local string_gsub = string.gsub
--

-- globals
local DRIVER_NAME = "cohere"

local _CHAT_ROLES = {
  ["system"] = "CHATBOT",
  ["assistant"] = "CHATBOT",
  ["user"] = "USER",
}
--

local function handle_stream_event(event_t, model_info, route_type)
  local metadata
  
  -- discard empty frames, it should either be a random new line, or comment
  if (not event_t.data) or (#event_t.data < 1) then
    return
  end

  local event, err = cjson.decode(event_t.data)
  if err then
    return nil, "failed to decode event frame from cohere: " .. err, nil
  end
  
  local new_event
  
  if event.event_type == "stream-start" then
    kong.ctx.plugin.ai_proxy_cohere_stream_id = event.generation_id
    
    -- ignore the rest of this one
    new_event = {
      choices = {
        [1] = {
          delta = {
            content = "",
            role = "assistant",
          },
          index = 0,
        },
      },
      id = event.generation_id,
      model = model_info.name,
      object = "chat.completion.chunk",
    }
    
  elseif event.event_type == "text-generation" then
    -- this is a token
    if route_type == "stream/llm/v1/chat" then
      new_event = {
        choices = {
          [1] = {
            delta = {
              content = event.text or "",
            },
            index = 0,
            finish_reason = cjson.null,
            logprobs = cjson.null,
          },
        },
        id = kong
         and kong.ctx
         and kong.ctx.plugin
         and kong.ctx.plugin.ai_proxy_cohere_stream_id,
        model = model_info.name,
        object = "chat.completion.chunk",
      }

    elseif route_type == "stream/llm/v1/completions" then
      new_event = {
        choices = {
          [1] = {
            text = event.text or "",
            index = 0,
            finish_reason = cjson.null,
            logprobs = cjson.null,
          },
        },
        id = kong
         and kong.ctx
         and kong.ctx.plugin
         and kong.ctx.plugin.ai_proxy_cohere_stream_id,
        model = model_info.name,
        object = "text_completion",
      }

    end

  elseif event.event_type == "stream-end" then
    -- return a metadata object, with the OpenAI termination event
    new_event = "[DONE]"

    metadata = {
      completion_tokens = event.response
                      and event.response.meta
                      and event.response.meta.billed_units
                      and event.response.meta.billed_units.output_tokens
              or 
                          event.response
                      and event.response.token_count
                      and event.response.token_count.response_tokens
              or 0,

      prompt_tokens = event.response
                  and event.response.meta
                  and event.response.meta.billed_units
                  and event.response.meta.billed_units.input_tokens
              or
                      event.response
                  and event.response.token_count
                  and event.token_count.prompt_tokens
              or 0,
    }
  end

  if new_event then
    if new_event ~= "[DONE]" then
      new_event = cjson.encode(new_event)
    end

    return new_event, nil, metadata
  else
    return nil, nil, metadata  -- caller code will handle "unrecognised" event types
  end
end


local function handle_json_inference_event(request_table, model)
  request_table.temperature = request_table.temperature
  request_table.max_tokens = request_table.max_tokens
  
  request_table.p = request_table.top_p
  request_table.k = request_table.top_k
  
  request_table.top_p = nil
  request_table.top_k = nil
  
  request_table.model = model.name or request_table.model
  request_table.stream = request_table.stream or false  -- explicitly set this
  
  if request_table.prompt and request_table.messages then
    return kong.response.exit(400, "cannot run a 'prompt' and a history of 'messages' at the same time - refer to schema")
    
  elseif request_table.messages then
    -- we have to move all BUT THE LAST message into "chat_history" array
    -- and move the LAST message (from 'user') into "message" string
    if #request_table.messages > 1 then
      local chat_history = table_new(#request_table.messages - 1, 0)
      for i, v in ipairs(request_table.messages) do
        -- if this is the last message prompt, don't add to history
        if i < #request_table.messages then
          local role
          if v.role == "assistant" or v.role == _CHAT_ROLES.assistant then
            role = _CHAT_ROLES.assistant
          else
            role = _CHAT_ROLES.user
          end
          
          chat_history[i] = {
            role = role,
            message = v.content,
          }
        end
      end
      
      request_table.chat_history = chat_history
    end
    
    request_table.message = request_table.messages[#request_table.messages].content
    request_table.messages = nil
    
  elseif request_table.prompt then
    request_table.prompt = request_table.prompt
    request_table.messages = nil
    request_table.message = nil
  end
  
  return request_table, "application/json", nil
end

local transformers_to = {
  ["llm/v1/chat"] = handle_json_inference_event,
  ["llm/v1/completions"] = handle_json_inference_event,
}

local transformers_from = {
  ["llm/v1/chat"] = function(response_string, model_info)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode cohere response"
    end

    -- messages/choices table is only 1 size, so don't need to static allocate
    local messages = {}
    messages.choices = {}
  
    if response_table.prompt and response_table.generations then
      -- this is a "co.generate"
      for i, v in ipairs(response_table.generations) do
        messages.choices[i] = {
          index = (i-1),
          text = v.text,
          finish_reason = "stop",
        }
      end
      messages.object = "text_completion"
      messages.model = model_info.name
      messages.id = response_table.id
  
      local stats = {
        completion_tokens = response_table.meta
                        and response_table.meta.billed_units
                        and response_table.meta.billed_units.output_tokens
                        or nil,

        prompt_tokens = response_table.meta
                    and response_table.meta.billed_units
                    and response_table.meta.billed_units.input_tokens
                    or nil,

        total_tokens = response_table.meta
                  and response_table.meta.billed_units
                  and (response_table.meta.billed_units.output_tokens + response_table.meta.billed_units.input_tokens)
                  or nil,
      }
      messages.usage = stats
  
    elseif response_table.text then
      -- this is a "co.chat"
  
      messages.choices[1] = {
        index = 0,
        message = {
          role = "assistant",
          content = response_table.text,
        },
        finish_reason = "stop",
      }
      messages.object = "chat.completion"
      messages.model = model_info.name
      messages.id = response_table.generation_id
  
      local stats = {
        completion_tokens = response_table.meta
                        and response_table.meta.billed_units
                        and response_table.meta.billed_units.output_tokens
                        or nil,

        prompt_tokens = response_table.meta
                    and response_table.meta.billed_units
                    and response_table.meta.billed_units.input_tokens
                    or nil,

        total_tokens = response_table.meta
                  and response_table.meta.billed_units
                  and (response_table.meta.billed_units.output_tokens + response_table.meta.billed_units.input_tokens)
                  or nil,
      }
      messages.usage = stats
  
    else -- probably a fault
      return nil, "'text' or 'generations' missing from cohere response body"
  
    end
  
    return cjson.encode(messages)
  end,

  ["llm/v1/completions"] = function(response_string, model_info)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode cohere response"
    end

    local prompt = {}
    prompt.choices = {}

    if response_table.prompt and response_table.generations then
      -- this is a "co.generate"

      for i, v in ipairs(response_table.generations) do
        prompt.choices[i] = {
          index = (i-1),
          text = v.text,
          finish_reason = "stop",
        }
      end
      prompt.object = "text_completion"
      prompt.model = model_info.name
      prompt.id = response_table.id

      local stats = {
        completion_tokens = response_table.meta and response_table.meta.billed_units.output_tokens or nil,
        prompt_tokens = response_table.meta and response_table.meta.billed_units.input_tokens or nil,
        total_tokens = response_table.meta
                  and (response_table.meta.billed_units.output_tokens + response_table.meta.billed_units.input_tokens)
                  or nil,
      }
      prompt.usage = stats

    elseif response_table.text then
      -- this is a "co.chat"

      prompt.choices[1] = {
        index = 0,
        message = {
          role = "assistant",
          content = response_table.text,
        },
        finish_reason = "stop",
      }
      prompt.object = "chat.completion"
      prompt.model = model_info.name
      prompt.id = response_table.generation_id
  
      local stats = {
        completion_tokens = response_table.token_count and response_table.token_count.response_tokens or nil,
        prompt_tokens = response_table.token_count and response_table.token_count.prompt_tokens or nil,
        total_tokens = response_table.token_count and response_table.token_count.total_tokens or nil,
      }
      prompt.usage = stats
  
    else -- probably a fault
      return nil, "'text' or 'generations' missing from cohere response body"
  
    end

    return cjson.encode(prompt)
  end,

  ["stream/llm/v1/chat"] = handle_stream_event,
  ["stream/llm/v1/completions"] = handle_stream_event,
}

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

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
    return nil, nil, fmt("error transforming to %s://%s", model_info.provider, route_type)
  end

  return response_object, content_type, nil
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
  -- check for user trying to bring own model
  if body and body.model then
    return false, "cannot use own model for this instance"
  end

  return true, nil
end

function _M.subrequest(body, conf, http_opts, return_res_table)
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

-- returns err or nil
function _M.configure_request(conf)
  local parsed_url

  if conf.model.options.upstream_url then
    parsed_url = socket_url.parse(conf.model.options.upstream_url)
  else
    parsed_url = socket_url.parse(ai_shared.upstream_url_format[DRIVER_NAME])
    parsed_url.path = conf.model.options
                      and conf.model.options.upstream_path
                      or ai_shared.operation_map[DRIVER_NAME][conf.route_type]
                      and ai_shared.operation_map[DRIVER_NAME][conf.route_type].path
                      or "/"

    if not parsed_url.path then
      return false, fmt("operation %s is not supported for cohere provider", conf.route_type)
    end
  end
  
  -- if the path is read from a URL capture, ensure that it is valid
  parsed_url.path = string_gsub(parsed_url.path, "^/*", "/")

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, (tonumber(parsed_url.port) or 443))

  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  if auth_header_name and auth_header_value then
    kong.service.request.set_header(auth_header_name, auth_header_value)
  end

  if auth_param_name and auth_param_value and auth_param_location == "query" then
    local query_table = kong.request.get_query()
    query_table[auth_param_name] = auth_param_value
    kong.service.request.set_query(query_table)
  end

  -- if auth_param_location is "form", it will have already been set in a pre-request hook
  return true, nil
end

return _M
