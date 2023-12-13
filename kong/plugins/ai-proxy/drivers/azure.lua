local _M = {}

-- imports
local fmt = string.format
local ai_shared = require("kong.plugins.ai-proxy.drivers.shared")
local openai_driver = require("kong.plugins.ai-proxy.drivers.openai")
local socket_url = require "socket.url"
--

_M.from_format = openai_driver.from_format
_M.to_format = openai_driver.to_format
_M.pre_request = openai_driver.pre_request
_M.header_filter_hooks = openai_driver.header_filter_hooks

function _M.post_request(conf)
  if ai_shared.clear_response_headers.azure then
    for i, v in ipairs(ai_shared.clear_response_headers.azure) do
      kong.response.clear_header(v)
    end
  end
end

-- returns err or nil
function _M.configure_request(conf)

  local parsed_url
  
  if conf.route_type ~= "preserve" then
    if conf.model.options.upstream_url then
      parsed_url = socket_url.parse(conf.model.options.upstream_url)
    else
      parsed_url = socket_url.parse(ai_shared.upstream_url_format.openai)

      local op_path = ai_shared.operation_map.openai[conf.route_type]
      if not op_path then
        return fmt("operation %s is not supported for openai provider", conf.route_type)
      end

      parsed_url.path = fmt(op_path, conf.model.name)
      parsed_url.host = fmt(parsed_url.host, conf.model.options.azure_instance)      
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
