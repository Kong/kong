local _M = {}

-- Voyage AI exposes embeddings, contextualized embeddings, multimodal
-- embeddings and rerank endpoints; it has no chat or completions API.
-- Therefore this driver can only be used with `route_type = "preserve"`:
-- the request path and body are forwarded to Voyage untouched, and only
-- the upstream target and the authentication are set by the plugin.

-- imports
local fmt = string.format
local ai_shared = require("kong.llm.drivers.shared")
local socket_url = require "socket.url"
local string_gsub = string.gsub
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
--

-- globals
local DRIVER_NAME = "voyage"
--

local function unsupported_route_type(route_type)
  return fmt("%s provider only supports the 'preserve' route_type, got '%s'",
             DRIVER_NAME, tostring(route_type))
end

function _M.from_format(response_string, model_info, route_type)
  return nil, unsupported_route_type(route_type)
end

function _M.to_format(request_table, model_info, route_type)
  if route_type == "preserve" then
    -- do nothing
    return request_table, nil, nil
  end

  return nil, nil, unsupported_route_type(route_type)
end

function _M.subrequest()
  return nil, nil, fmt("%s provider does not support plugin subrequests", DRIVER_NAME)
end

function _M.header_filter_hooks(body)
  -- nothing to parse in header_filter phase
end

function _M.post_request(conf)
  -- nothing to clear
end

function _M.pre_request(conf, body)
  kong.service.request.set_header("Accept-Encoding", "gzip, identity") -- tell server not to send brotli

  return true, nil
end

-- returns err or nil
function _M.configure_request(conf)
  local model = ai_plugin_ctx.get_request_model_table_inuse()
  if not model or type(model) ~= "table" or model.provider ~= DRIVER_NAME then
    return nil, "invalid model parameter"
  end

  local parsed_url
  if model.options and model.options.upstream_url then
    parsed_url = socket_url.parse(model.options.upstream_url)
  else
    parsed_url = socket_url.parse(ai_shared.upstream_url_format[DRIVER_NAME])
    parsed_url.path = (model.options and model.options.upstream_path) or "/"
  end

  ai_shared.override_upstream_url(parsed_url, conf, model)

  parsed_url.path = string_gsub(parsed_url.path or "/", "^/*", "/")

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

  -- if auth_param_location is "form", it will have already been set in a global pre-request hook
  return true, nil
end

return _M
