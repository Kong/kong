local stringy = require "stringy"
local url = require("socket.url")
local cache = require "kong.tools.database_cache"

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
  local api = nil
  for _,host in ipairs(hosts) do
    api = cache.get_and_set(cache.api_key(host), function()
      local apis, err = dao.apis:find_by_keys { public_dns = host }
      if err then
        ngx.log(ngx.ERR, tostring(err))
        utils.show_error(500, tostring(err))
      elseif apis and #apis == 1 then
        return apis[1]
      end
    end)
    if api then break end
  end

  if not api then
    utils.not_found("API not found with Host: "..table.concat(hosts, ","))
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
