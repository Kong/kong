local url = require "socket.url"
local cache = require "kong.tools.database_cache"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

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

-- Find an API from a request made to nginx. Either from one of the Host or X-Host-Override headers
-- matching the API's `public_dns`, either from the `request_uri` matching the API's `path`.
--
-- To perform this, we need to query _ALL_ APIs in memory. It is the only way to compare the `request_uri`
-- as a regex to the values set in DB. We keep APIs in the database cache for a longer time than usual.
-- @see https://github.com/Mashape/kong/issues/15 for an improvement on this.
--
-- @return `err`         Any error encountered during the retrieval.
-- @return `api`         The retrieved API, if any.
-- @return `hosts`       The list of headers values found in Host and X-Host-Override.
-- @return `request_uri` The URI for this request.
local function find_api()
  local retrieved_api

  -- retrieve all APIs
  local apis_dics, err = cache.get_or_set("APIS_BY_PUBLIC_DNS", function()
    local apis, err = dao.apis:find_all()
    if err then
      return nil, err
    end

    -- build dictionnaries of public_dns:api and path:apis for efficient lookup.
    local dns_dic, path_dic = {}, {}
    for _, api in ipairs(apis) do
      if api.public_dns then
        dns_dic[api.public_dns] = api
      end
      if api.path then
        path_dic[api.path] = api
      end
    end
    return {dns = dns_dic, path = path_dic}
  end, 60) -- 60 seconds cache

  if err then
    return err
  end

  -- find by Host header
  local all_hosts = {}
  for _, header_name in ipairs({"Host", constants.HEADERS.HOST_OVERRIDE}) do
    local hosts = ngx.req.get_headers()[header_name]
    if hosts then
      if type(hosts) == "string" then
        hosts = {hosts}
      end
      -- for all values of this header, try to find an API using the apis_by_dns dictionnary
      for _, host in ipairs(hosts) do
        table.insert(all_hosts, host)
        if apis_dics.dns[host] then
          retrieved_api = apis_dics.dns[host]
          break
        end
      end
    end
  end

  -- If it was found by Host, return
  if retrieved_api then
    return nil, retrieved_api
  end

  -- Otherwise, we look for it by path. We have to loop over all APIs and compare the requested URI.
  local request_uri = ngx.var.request_uri
  for path, api in pairs(apis_dics.path) do
    local m, err = ngx.re.match(request_uri, path)
    if err then
      ngx.log(ngx.ERR, "[resolver] error matching requested path: "..err)
    elseif m then
      retrieved_api = api
    end
  end

  return nil, retrieved_api, all_hosts, request_uri
end

-- Retrieve the API from the Host that has been requested
function _M.execute(conf)
  local err, api, hosts, request_uri = find_api()
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  elseif not api then
    return responses.send_HTTP_NOT_FOUND {
      message = "API not found with these values",
      public_dns = hosts,
      path = request_uri
    }
  end

  -- Setting the backend URL for the proxy_pass directive
  ngx.var.backend_url = get_backend_url(api)..ngx.var.request_uri
  ngx.req.set_header("Host", get_host_from_url(ngx.var.backend_url))

  ngx.ctx.api = api
end

return _M
