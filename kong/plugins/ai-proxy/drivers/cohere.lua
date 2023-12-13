local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.plugins.ai-proxy.drivers.shared")
local socket_url = require "socket.url"
local http = require("resty.http")
local table_new = require("table.new")
--

local transformers_to = {
  ["llm/v1/chat"] = function(request_table, model)
    request_table.model = model.name

    if request_table.prompt and request_table.messages then
      return kong.response.exit(400, "cannot run a 'prompt' and a history of 'messages' at the same time - refer to schema")
  
    elseif request_table.messages then
      -- we have to move all BUT THE LAST message into "chat_history" array
      -- and move the LAST message (from 'user') into "message" string
      local chat_history = table_new(#request_table.messages - 1, 0)
      for i, v in ipairs(request_table.messages) do
        -- if this is the last message prompt, don't add to history
        if i < #request_table.messages then
          local role
          if v.role == "assistant" or v.role == "CHATBOT" then
            role = "CHATBOT"
          else
            role = "USER"
          end
  
          chat_history[i] = {
            role = role,
            message = v.content,
          }
        end
      end


      request_table.chat_history = chat_history
      request_table.temperature = model.options.temperature
      request_table.message = request_table.messages[#request_table.messages].content
      request_table.messages = nil

    elseif request_table.prompt then
      request_table.temperature = model.options.temperature
      request_table.max_tokens = model.options.max_tokens
      request_table.truncate = request_table.truncate or "END"
      request_table.return_likelihoods = request_table.return_likelihoods or "NONE"
      request_table.p = model.options.top_p
      request_table.k = model.options.top_k

    end

    return request_table, "application/json", nil
  end,

  ["llm/v1/completions"] = function(request_table, model)
    request_table.model = model.name

    if request_table.prompt and request_table.messages then
      return kong.response.exit(400, "cannot run a 'prompt' and a history of 'messages' at the same time - refer to schema")
  
    elseif request_table.messages then
      -- we have to move all BUT THE LAST message into "chat_history" array
      -- and move the LAST message (from 'user') into "message" string
      local chat_history = table_new(#request_table.messages - 1, 0)
      for i, v in ipairs(request_table.messages) do
        -- if this is the last message prompt, don't add to history
        if i < #request_table.messages then
          local role
          if v.role == "assistant" or v.role == "CHATBOT" then
            role = "CHATBOT"
          else
            role = "USER"
          end
          
          chat_history[i] = {
            role = role,
            message = v.content,
          }
        end
      end

      request_table.chat_history = chat_history
      request_table.temperature = model.options.temperature
      request_table.message = request_table.messages[#request_table.messages].content
      request_table.messages = nil

    elseif request_table.prompt then
      request_table.temperature = model.options.temperature
      request_table.max_tokens = model.options.max_tokens
      request_table.truncate = request_table.truncate or "END"
      request_table.return_likelihoods = request_table.return_likelihoods or "NONE"
      request_table.p = model.options.top_p
      request_table.k = model.options.top_k

    end

    return request_table, "application/json", nil
  end,
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
        completion_tokens = response_table.token_count and response_table.token_count.response_tokens or nil,
        prompt_tokens = response_table.token_count and response_table.token_count.prompt_tokens or nil,
        total_tokens = response_table.token_count and response_table.token_count.total_tokens or nil,
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
}

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  if not transformers_from[route_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end

  local ok, response_string, err = pcall(transformers_from[route_type], response_string, model_info)
  if not ok or err then
    return nil, fmt("transformation failed from type %s://%s: %s",
                    model_info.provider,
                    route_type,
                    err or "unexpected_error"
                  )
  end

  return response_string, nil
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

function _M.subrequest(body_table, route_type, auth)
  local body_string, err = cjson.encode(body_table)
  if err then return nil, "failed to parse body to json: " .. err end

  local httpc = http.new()

  local request_url = fmt(
    "%s%s",
    ai_shared.upstream_url_format.cohere,
    ai_shared.operation_map.cohere[route_type]
  )

  local res, err = httpc:request_uri(
    request_url,
    {
      method = "POST",
      body = body_string,
      headers = {
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
        [auth.header_name] = auth.header_value,
      },
    })
  if not res then
    return nil, "request failed: " .. err
  end

  -- At this point, the entire request / response is complete and the connection
  -- will be closed or back on the connection pool.
  local status = res.status
  local body   = res.body

  if status ~= 200 then
    return body, "status code not 200"
  end

  return body, nil
end

function _M.header_filter_hooks(body)
  -- nothing to parse in header_filter phase
end

function _M.post_request(conf)
  if ai_shared.clear_response_headers.cohere then
    for i, v in ipairs(ai_shared.clear_response_headers.cohere) do
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

-- returns err or nil
function _M.configure_request(conf)
  local parsed_url
  
  if conf.route_type ~= "preserve" then
    if conf.model.options.upstream_url then
      parsed_url = socket_url.parse(conf.model.options.upstream_url)
    else
      parsed_url = socket_url.parse(ai_shared.upstream_url_format.cohere)
      parsed_url.path = ai_shared.operation_map.cohere[conf.route_type]

      if not parsed_url.path then
        return false, fmt("operation %s is not supported for cohere provider", conf.route_type)
      end
    end
    
    kong.service.request.set_path(parsed_url.path)
    kong.service.request.set_scheme(parsed_url.scheme)
    kong.service.set_target(parsed_url.host, tonumber(parsed_url.port))
  end

  local auth_header_name = conf.auth.header_name
  local auth_header_value = conf.auth.header_value
  local auth_param_name = conf.auth.param_name
  local auth_param_value = conf.auth.param_value
  local auth_param_location = conf.auth.param_location

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
