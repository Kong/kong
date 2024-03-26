local _M = {}

-- imports
local cjson = require("cjson.safe")
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local openai_driver = require("kong.llm.drivers.openai")
local socket_url = require "socket.url"
--

-- globals
local DRIVER_NAME = "azure"
--

_M.from_format = openai_driver.from_format
_M.to_format = openai_driver.to_format
_M.pre_request = openai_driver.pre_request
_M.header_filter_hooks = openai_driver.header_filter_hooks

function _M.post_request(conf)
  if ai_shared.clear_response_headers[DRIVER_NAME] then
    for i, v in ipairs(ai_shared.clear_response_headers[DRIVER_NAME]) do
      kong.response.clear_header(v)
    end
  end
end

function _M.subrequest(body, conf, http_opts, return_res_table)
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

  -- azure has non-standard URL format
  local url = (conf.model.options and conf.model.options.upstream_url)
  or fmt(
    "%s%s?api-version=%s",
    ai_shared.upstream_url_format[DRIVER_NAME]:format(conf.model.options.azure_instance, conf.model.options.azure_deployment_id),
    ai_shared.operation_map[DRIVER_NAME][conf.route_type].path,
    conf.model.options.azure_api_version or "2023-05-15"
  )

  local method = ai_shared.operation_map[DRIVER_NAME][conf.route_type].method

  local headers = {
    ["Accept"] = "application/json",
    ["Content-Type"] = "application/json",
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

-- returns err or nil
function _M.configure_request(conf)

  local parsed_url

  if conf.model.options.upstream_url then
    parsed_url = socket_url.parse(conf.model.options.upstream_url)
  else
    -- azure has non-standard URL format
    local url = fmt(
      "%s%s",
      ai_shared.upstream_url_format[DRIVER_NAME]:format(conf.model.options.azure_instance, conf.model.options.azure_deployment_id),
      ai_shared.operation_map[DRIVER_NAME][conf.route_type].path
    )
    parsed_url = socket_url.parse(url)
  end

  kong.service.request.set_path(parsed_url.path)
  kong.service.request.set_scheme(parsed_url.scheme)
  kong.service.set_target(parsed_url.host, tonumber(parsed_url.port))


  local auth_header_name = conf.auth and conf.auth.header_name
  local auth_header_value = conf.auth and conf.auth.header_value
  local auth_param_name = conf.auth and conf.auth.param_name
  local auth_param_value = conf.auth and conf.auth.param_value
  local auth_param_location = conf.auth and conf.auth.param_location

  if auth_header_name and auth_header_value then
    kong.service.request.set_header(auth_header_name, auth_header_value)
  end

  local query_table = kong.request.get_query()

  -- technically min supported version
  query_table["api-version"] = conf.model.options and conf.model.options.azure_api_version or "2023-05-15"
  
  if auth_param_name and auth_param_value and auth_param_location == "query" then
    query_table[auth_param_name] = auth_param_value
  end

  kong.service.request.set_query(query_table)

  -- if auth_param_location is "form", it will have already been set in a pre-request hook
  return true, nil
end


return _M
