
local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local openai_driver = require("kong.llm.drivers.openai")
local socket_url = require "socket.url"
local string_gsub = string.gsub
--

-- globals
local DRIVER_NAME = "mistral"
--

-- transformer mappings
local transformers_from = {
  ["llm/v1/chat/ollama"] = ai_shared.from_ollama,
  ["llm/v1/completions/ollama"] = ai_shared.from_ollama,
  ["stream/llm/v1/chat/ollama"] = ai_shared.from_ollama,
  ["stream/llm/v1/completions/ollama"] = ai_shared.from_ollama,
}

local transformers_to = {
  ["llm/v1/chat/ollama"] = ai_shared.to_ollama,
  ["llm/v1/completions/ollama"] = ai_shared.to_ollama,
}
--

function _M.from_format(response_string, model_info, route_type)
  -- MUST return a string, to set as the response body
  ngx.log(ngx.DEBUG, "converting from ", model_info.provider, "://", route_type, " type to kong")

  if model_info.options.mistral_format == "openai" then
    return openai_driver.from_format(response_string, model_info, route_type)
  end

  local transformer_type = fmt("%s/%s", route_type, model_info.options.mistral_format)
  if not transformers_from[transformer_type] then
    return nil, fmt("no transformer available from format %s://%s", model_info.provider, transformer_type)
  end

  local ok, response_string, err = pcall(
    transformers_from[transformer_type],
    response_string,
    model_info,
    route_type
  )
  if not ok or err then
    return nil, fmt("transformation failed from type %s://%s/%s: %s", model_info.provider, route_type, model_info.options.mistral_version, err or "unexpected_error")
  end

  return response_string, nil
end

function _M.to_format(request_table, model_info, route_type)
  ngx.log(ngx.DEBUG, "converting from kong type to ", model_info.provider, "://", route_type)

  if model_info.options.mistral_format == "openai" then
    return openai_driver.to_format(request_table, model_info, route_type)
  end

  local transformer_type = fmt("%s/%s", route_type, model_info.options.mistral_format)
  if not transformers_to[transformer_type] then
    return nil, nil, fmt("no transformer available to format %s://%s", model_info.provider, transformer_type)
  end

  request_table = ai_shared.merge_config_defaults(request_table, model_info.options, model_info.route_type)

  -- dynamically call the correct transformer
  local ok, response_object, content_type, err = pcall(
    transformers_to[transformer_type],
    request_table,
    model_info
  )
  if err or (not ok) then
    return nil, nil, fmt("error transforming to %s://%s", model_info.provider, route_type)
  end

  return response_object, content_type, nil
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

  local url = conf.model.options.upstream_url

  local method = "POST"

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json"
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

function _M.pre_request(conf, body)
  return true, nil
end

function _M.post_request(conf)
  if ai_shared.clear_response_headers[DRIVER_NAME] then
    for i, v in ipairs(ai_shared.clear_response_headers[DRIVER_NAME]) do
      kong.response.clear_header(v)
    end
  end
end

-- returns err or nil
function _M.configure_request(conf)
  local parsed_url

  -- mistral shared operation paths
  if (conf.model.options and conf.model.options.upstream_url) then
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
  parsed_url.path = (parsed_url.path and string_gsub(parsed_url.path, "^/*", "/")) or "/"

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, (tonumber(parsed_url.port) or 443))

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
