local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.plugins.ai-proxy.drivers.shared")
local socket_url = require "socket.url"
local http = require("resty.http")
--

local transformers_to = {
  ["llm/v1/chat"] = function(request_table, model, max_tokens, temperature, top_p)
    -- if user passed a prompt as a chat, transform it to a chat message
    if request_table.prompt then
      request_table.messages = {
        {
          role = "user",
          content = request_table.prompt,
        }
      }
    end
  
    local this = {
      model = model,
      messages = request_table.messages,
      max_tokens = max_tokens,
      temperature = temperature,
      top_p = top_p,
    }
  
    return this, "application/json", nil
  end,

  ["llm/v1/completions"] = function(request_table, model, max_tokens, temperature, top_p)
    local this = {
      prompt = request_table.prompt,
      model = model,
      max_tokens = max_tokens,
      temperature = temperature,
    }
  
    return this, "application/json", nil
  end,
}

local transformers_from = {
  ["llm/v1/chat"] = function(response_string, model_info)
    local response_object, err = cjson.decode(response_string)
    if err then
      return nil, "'choices' not in llm/v1/chat response"
    end

    if response_object.choices then
      return response_string, nil
    else
      return nil, "'choices' not in llm/v1/chat response"
    end
  end,

  ["llm/v1/completions"] = function(response_string, model_info)
    local response_object, err = cjson.decode(response_string)
    if err then
      return nil, "'choices' not in llm/v1/completions response"
    end

    if response_object.choices then
      return response_string, nil
    else
      return nil, "'choices' not in llm/v1/completions response"
    end
  end,
}

function _M.from_format(response_string, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  -- MUST return a string, to set as the response body
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
    model_info.name,
    (model_info.options and model_info.options.max_tokens),
    (model_info.options and model_info.options.temperature),
    (model_info.options and model_info.options.top_p)
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
    ai_shared.upstream_url_format.openai,
    ai_shared.operation_map.openai[route_type]
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
  if ai_shared.clear_response_headers.openai then
    for i, v in ipairs(ai_shared.clear_response_headers.openai) do
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
    if (conf.model.options and conf.model.options.upstream_url) then
      parsed_url = socket_url.parse(conf.model.options.upstream_url)
    else
      local path = ai_shared.operation_map.openai[conf.route_type]
      if not path then
        return false, fmt("operation %s is not supported for openai provider", conf.route_type)
      end
      
      parsed_url = socket_url.parse(ai_shared.upstream_url_format.openai)
      parsed_url.path = path
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

  -- if auth_param_location is "form", it will have already been set in a global pre-request hook
  return true, nil
end

return _M
