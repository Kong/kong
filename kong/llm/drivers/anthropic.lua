local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require "socket.url"
local buffer = require("string.buffer")
--

-- globals
local DRIVER_NAME = "anthropic"
--

local function kong_prompt_to_claude_prompt(prompt)
  return fmt("Human: %s\n\nAssistant:", prompt)
end

local function kong_messages_to_claude_prompt(messages)
  local buf = buffer.new()
  buf:reset()

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


local function to_claude_prompt(req)
  if req.prompt then
    return kong_prompt_to_claude_prompt(req.prompt)

  elseif req.messages then
    return kong_messages_to_claude_prompt(req.messages)

  end
  
  return nil, "request is missing .prompt and .messages commands"
end


local transformers_to = {
  ["llm/v1/chat"] = function(request_table, model)
    local prompt = {}
    local err

    prompt.prompt, err = to_claude_prompt(request_table)
    if err then 
      return nil, nil, err
    end
    
    prompt.temperature = (model.options and model.options.temperature) or nil
    prompt.max_tokens_to_sample = (model.options and model.options.max_tokens) or nil
    prompt.model = model.name

    return prompt, "application/json", nil
  end,

  ["llm/v1/completions"] = function(request_table, model)
    local prompt = {}
    local err

    prompt.prompt, err = to_claude_prompt(request_table)
    if err then
      return nil, nil, err
    end
    
    prompt.temperature = (model.options and model.options.temperature) or nil
    prompt.max_tokens_to_sample = (model.options and model.options.max_tokens) or nil
    prompt.model = model.name

    return prompt, "application/json", nil
  end,
}

local transformers_from = {
  ["llm/v1/chat"] = function(response_string)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode cohere response"
    end

    if response_table.completion then
      local res = {
        choices = {
          {
            index = 0,
            message = {
              role = "assistant",
              content = response_table.completion,
            },
            finish_reason = response_table.stop_reason,
          },
        },
        model = response_table.model,
        object = "chat.completion",
      }
        
      return cjson.encode(res)
    else
      -- it's probably an error block, return generic error
      return nil, "'completion' not in anthropic://llm/v1/chat response"
    end
  end,

  ["llm/v1/completions"] = function(response_string)
    local response_table, err = cjson.decode(response_string)
    if err then
      return nil, "failed to decode cohere response"
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
}

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  local transform = transformers_from[route_type]
  if not transform then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, route_type)
  end
  
  local ok, response_string, err = pcall(transform, response_string)
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

  local res, err = ai_shared.http_request(url, body_string, method, headers, http_opts)
  if err then
    return nil, nil, "request to ai service failed: " .. err
  end

  if return_res_table then
    return res, res.status, nil
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
  -- check for user trying to bring own model
  if body and body.model then
    return nil, "cannot use own model for this instance"
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
      parsed_url = socket_url.parse(ai_shared.upstream_url_format[DRIVER_NAME])
      parsed_url.path = ai_shared.operation_map[DRIVER_NAME][conf.route_type].path

      if not parsed_url.path then
        return nil, fmt("operation %s is not supported for anthropic provider", conf.route_type)
      end
    end

    kong.service.request.set_path(parsed_url.path)
    kong.service.request.set_scheme(parsed_url.scheme)
    kong.service.set_target(parsed_url.host, tonumber(parsed_url.port))
  end

  kong.service.request.set_header("anthropic-version", conf.model.options.anthropic_version)

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
