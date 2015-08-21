local url = require "socket.url"
local cache = require "kong.tools.database_cache"
local stringy = require "stringy"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

local _M = {}

-- Take a public_dns and make it a pattern for wildcard matching.
-- Only do so if the public_dns actually has a wildcard.
local function create_wildcard_pattern(public_dns)
  if string.find(public_dns, "*", 1, true) then
    local pattern = string.gsub(public_dns, "%.", "%%.")
    pattern = string.gsub(pattern, "*", ".+")
    pattern = string.format("^%s$", pattern)
    return pattern
  end
end

-- Handles pattern-specific characters if any.
local function create_strip_path_pattern(path)
  return string.gsub(path, "[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%"..c end)
end

local function get_backend_url(api)
  local result = api.target_url

  -- Checking if the target url ends with a final slash
  local len = string.len(result)
  if string.sub(result, len, len) == "/" then
    -- Remove one slash to avoid having a double slash
    -- Because ngx.var.uri always starts with a slash
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

-- Load all APIs in memory.
-- Sort the data for faster lookup: dictionary per public_dns and an array of wildcard public_dns.
function _M.load_apis_in_memory()
  local apis, err = dao.apis:find_all()
  if err then
    return nil, err
  end

  -- build dictionnaries of public_dns:api for efficient O(1) lookup.
  -- we only do O(n) lookup for wildcard public_dns and path that are in arrays.
  local dns_dic, dns_wildcard_arr, path_arr = {}, {}, {}
  for _, api in ipairs(apis) do
    if api.public_dns then
      local pattern = create_wildcard_pattern(api.public_dns)
      if pattern then
        -- If the public_dns is a wildcard, we have a pattern and we can
        -- store it in an array for later lookup.
        table.insert(dns_wildcard_arr, {pattern = pattern, api = api})
      else
        -- Keep non-wildcard public_dns in a dictionary for faster lookup.
        dns_dic[api.public_dns] = api
      end
    end
    if api.path then
      table.insert(path_arr, {
        api = api,
        path = api.path,
        strip_path_pattern = create_strip_path_pattern(api.path)
      })
    end
  end

  return {
    by_dns = dns_dic,
    path_arr = path_arr, -- all APIs with a path
    wildcard_dns_arr = dns_wildcard_arr -- all APIs with a wildcard public_dns
  }
end

function _M.find_api_by_public_dns(req_headers, apis_dics)
  local all_hosts = {}
  for _, header_name in ipairs({"Host", constants.HEADERS.HOST_OVERRIDE}) do
    local hosts = req_headers[header_name]
    if hosts then
      if type(hosts) == "string" then
        hosts = {hosts}
      end
      -- for all values of this header, try to find an API using the apis_by_dns dictionnary
      for _, host in ipairs(hosts) do
        host = unpack(stringy.split(host, ":"))
        table.insert(all_hosts, host)
        if apis_dics.by_dns[host] then
          return apis_dics.by_dns[host]
        else
          -- If the API was not found in the dictionary, maybe it is a wildcard public_dns.
          -- In that case, we need to loop over all of them.
          for _, wildcard_dns in ipairs(apis_dics.wildcard_dns_arr) do
            if string.match(host, wildcard_dns.pattern) then
              return wildcard_dns.api
            end
          end
        end
      end
    end
  end

  return nil, all_hosts
end

-- To do so, we have to compare entire URI segments (delimited by "/").
-- Comparing by entire segment allows us to avoid edge-cases such as:
-- uri = /mockbin-with-pattern/xyz
-- api.path regex = ^/mockbin
-- ^ This would wrongfully match. Wether:
-- api.path regex = ^/mockbin/
-- ^ This does not match.

-- Because we need to compare by entire URI segments, all URIs need to have a trailing slash, otherwise:
-- uri = /mockbin
-- api.path regex = ^/mockbin/
-- ^ This would not match.
-- @param  `uri` The URI for this request.
-- @param  `path_arr`    An array of all APIs that have a path property.
function _M.find_api_by_path(uri, path_arr)
  if not stringy.endswith(uri, "/") then
    uri = uri.."/"
  end

  for _, item in ipairs(path_arr) do
    local m, err = ngx.re.match(uri, "^"..item.path.."/")
    if err then
      ngx.log(ngx.ERR, "[resolver] error matching requested path: "..err)
    elseif m then
      return item.api, item.strip_path_pattern
    end
  end
end

-- Replace `/path` with `path`, and then prefix with a `/`
-- or replace `/path/foo` with `/foo`, and then do not prefix with `/`.
function _M.strip_path(uri, strip_path_pattern)
  local uri = string.gsub(uri, strip_path_pattern, "", 1)
  if string.sub(uri, 0, 1) ~= "/" then
    uri = "/"..uri
  end
  return uri
end

-- Find an API from a request made to nginx. Either from one of the Host or X-Host-Override headers
-- matching the API's `public_dns`, either from the `uri` matching the API's `path`.
--
-- To perform this, we need to query _ALL_ APIs in memory. It is the only way to compare the `uri`
-- as a regex to the values set in DB, as well as matching wildcard dns.
-- We keep APIs in the database cache for a longer time than usual.
-- @see https://github.com/Mashape/kong/issues/15 for an improvement on this.
--
-- @param  `uri` The URI for this request.
-- @return `err`         Any error encountered during the retrieval.
-- @return `api`         The retrieved API, if any.
-- @return `hosts`       The list of headers values found in Host and X-Host-Override.
-- @return `strip_path_pattern` If the API was retrieved by path, contain the pattern to strip it from the URI.
local function find_api(uri)
  local api, all_hosts, strip_path_pattern

  -- Retrieve all APIs
  local apis_dics, err = cache.get_or_set("ALL_APIS_BY_DIC", _M.load_apis_in_memory, 60) -- 60 seconds cache, longer than usual
  if err then
    return err
  end

  -- Find by Host header
  api, all_hosts = _M.find_api_by_public_dns(ngx.req.get_headers(), apis_dics)

  -- If it was found by Host, return
  if api then
    return nil, api, all_hosts
  end

  -- Otherwise, we look for it by path. We have to loop over all APIs and compare the requested URI.
  api, strip_path_pattern = _M.find_api_by_path(uri, apis_dics.path_arr)

  return nil, api, all_hosts, strip_path_pattern
end

function _M.execute(conf)
  local uri = ngx.var.uri
  local err, api, hosts, strip_path_pattern = find_api(uri)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  elseif not api then
    return responses.send_HTTP_NOT_FOUND {
      message = "API not found with these values",
      public_dns = hosts,
      path = uri
    }
  end

  -- If API was retrieved by path and the path needs to be stripped
  if strip_path_pattern and api.strip_path then
    uri = _M.strip_path(uri, strip_path_pattern)
  end

  -- Setting the backend URL for the proxy_pass directive
  ngx.var.backend_url = get_backend_url(api)..uri
  if api.preserve_host then
    ngx.var.backend_host = ngx.req.get_headers()["host"]
  else
    ngx.var.backend_host = get_host_from_url(ngx.var.backend_url)
  end

  ngx.ctx.api = api
end

return _M
