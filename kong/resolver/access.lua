local url = require("socket.url")
local stringy = require "stringy"
local responses = require "kong.tools.responses"
local resolver_util = require "kong.resolver.resolver_util"

local _M = {}

local function get_backend_url(api)
  local result = api.target_url

  -- Checking if the target url ends with a final slash
  local len = string.len(result)
  if string.sub(result, len, len) == "/" then
    -- Remove one slash to avoid having a double slash
    -- Because ngx.var.request_uri always starts with a slash
    result = string.sub(result, 0, len - 1)
  end

  return result
end

local function get_host_from_url(val)
  local parsed_url = url.parse(val)

  local port
  if parsed_url.port then
     port = parsed_url.port
  elseif parsed_url.scheme == "https" then
    port = 443
  end

  return parsed_url.host..(port and ":"..port or "")
end

local function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and stringy.startswith(headers["expect"], "100")
end

-- Retrieve the API from the Host that has been requested
function _M.execute(conf)
  local hosts = ngx.req.get_headers()["host"] -- Multiple "Host" can have been requested

  if type(hosts) == "string" then
    hosts = { hosts }
  elseif not hosts then
    hosts = {}
  end

  -- Find the API
  local api, err = resolver_util.find_api(hosts)

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  elseif not api then
    return responses.send_HTTP_NOT_FOUND("API not found with Host: "..table.concat(hosts, ","))
  end

  -- Setting the backend URL for the proxy_pass directive
  ngx.var.backend_url = get_backend_url(api)..ngx.var.request_uri

  ngx.req.set_header("host", get_host_from_url(ngx.var.backend_url))

  -- There are some requests whose authentication needs to be skipped
  if not skip_authentication(ngx.req.get_headers()) then
    -- Saving these properties for the other plugins handlers
    ngx.ctx.api = api
  end
end

return _M
