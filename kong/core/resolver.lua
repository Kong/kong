local singletons = require "kong.singletons"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"

local table_insert = table.insert
local table_sort = table.sort
local re_match = ngx.re.match
local re_find = ngx.re.find
local sub = string.sub
local gsub = string.gsub
local log = ngx.log
local ERR = ngx.ERR
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local ipairs = ipairs
local type = type

local _M = {}

-- Handles pattern-specific characters if any.
local function create_strip_request_path_pattern(request_path)
  return request_path:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%"..c end)
end

local function get_host_from_upstream_url(val)
  local m, err = re_match(val, "^(http[s]?):\\/\\/([^:\\/\\s]+):?([0-9]*)\\/?", "oj")
  if err then
    log(ERR, "[resolver] error extracting host from upstream_url: ", err)
    return
  elseif m then
    local scheme, host, port = m[1], m[2], m[3] -- avoid unpack()
    if scheme == "https" then
      return host .. ":443"
    elseif port ~= "" then
      return host .. ":" .. port
    else
      return host
    end
  end
end

-- Load all APIs in memory.
-- Sort the data for faster lookup: dictionary per request_host and an array of wildcard request_host.
function _M.load_apis_in_memory()
  local apis, err = singletons.dao.apis:find_all()
  if err then
    return nil, err
  end

  -- build dictionnaries of request_host:api for efficient O(1) lookup.
  -- we only do O(n) lookup for wildcard request_host and request_path that are in arrays.
  local dns_dic, dns_wildcard_arr, request_path_arr = {}, {}, {}
  for _, api in ipairs(apis) do
    if api.request_host then
      if api.request_host:find("*", 1, true) then
        -- If the request_host is a wildcard, we have a pattern and we can
        -- store it in an array for later lookup.
        dns_wildcard_arr[#dns_wildcard_arr+1] = {
          regex = "^"..api.request_host:gsub("%.", "\\."):gsub("*", ".+").."$",
          api = api
        }
      else
        -- Keep non-wildcard request_host in a dictionary for faster lookup.
        dns_dic[api.request_host] = api
      end
    end
    if api.request_path then
      table_insert(request_path_arr, {
        api = api,
        request_path = api.request_path,
        request_path_regex = "^"..(api.request_path == "/" and "/" or api.request_path.."/"),
        strip_request_path_pattern = create_strip_request_path_pattern(api.request_path)
      })
    end
  end

  -- Sort request_path_arr by descending specificity.
  table_sort(request_path_arr, function (first, second)
    return first.request_path > second.request_path
  end)

  return {
    by_dns = dns_dic,
    request_path_arr = request_path_arr, -- all APIs with a request_path
    wildcard_dns_arr = dns_wildcard_arr -- all APIs with a wildcard request_host
  }
end

function _M.find_api_by_request_host(req_headers, apis_dics)
  local hosts_list = {}
  for _, header_name in ipairs({"Host", constants.HEADERS.HOST_OVERRIDE}) do
    local hosts = req_headers[header_name]
    if hosts then
      if type(hosts) == "string" then
        hosts = {hosts}
      end
      -- for all values of this header, try to find an API using the apis_by_dns dictionnary
      for _, host in ipairs(hosts) do
        local m, err = re_match(host, "^([^:]+)", "oj") -- grab everything before ":"
        if err then
          log(ERR, "[resolver] error stripping port number from host: ", err)
          return
        end

        host = m[1]
        hosts_list[#hosts_list+1] = host

        if apis_dics.by_dns[host] then
          return apis_dics.by_dns[host], host
        else
          -- If the API was not found in the dictionary, maybe it is a wildcard request_host.
          -- In that case, we need to loop over all of them.
          for _, wildcard_dns in ipairs(apis_dics.wildcard_dns_arr) do
            local m, err = re_match(host, wildcard_dns.regex, "oj")
            if err then
              log(ERR, "[resolver] error matching wildcard DNS from request_host: ", err)
              return
            end

            if m then
              return wildcard_dns.api
            end
          end
        end
      end
    end
  end

  return nil, nil, hosts_list
end

-- To do so, we have to compare entire URI segments (delimited by "/").
-- Comparing by entire segment allows us to avoid edge-cases such as:
-- uri_path = /mockbin-with-pattern/xyz
-- api.request_path regex = ^/mockbin
-- ^ This would wrongfully match. Wether:
-- api.request_path regex = ^/mockbin/
-- ^ This does not match.

-- Because we need to compare by entire URI segments, all URIs need to have a trailing slash, otherwise:
-- uri_path = /mockbin
-- api.request_path regex = ^/mockbin/
-- ^ This would not match.
-- @param  `uri` The URI for this request.
-- @param  `request_path_arr`    An array of all APIs that have a request_path property.
function _M.find_api_by_request_path(uri_path, request_path_arr)
  if sub(uri_path, -1) ~= "/" then
    uri_path = uri_path.."/"
  end

  for _, item in ipairs(request_path_arr) do
    local from, _, err = re_find(uri_path, item.request_path_regex, "oj")
    if err then
      log(ERR, "[resolver] error matching requested request_path: ", err)
    elseif from then
      return item.api, item.strip_request_path_pattern
    end
  end
end

-- Replace `/request_path` with `request_path`, and then prefix with a `/`
-- or replace `/request_path/foo` with `/foo`, and then do not prefix with `/`.
function _M.strip_request_path(uri, strip_request_path_pattern, upstream_url_has_path)
  local uri = gsub(uri, strip_request_path_pattern, "", 1)

  -- Sometimes uri can be an empty string, and adding a slash "/"..uri will lead to a trailing slash
  -- We don't want to add a trailing slash in one specific scenario, when the upstream_url already has
  -- a path (so it's not root, like http://hello.com/, but http://hello.com/path) in order to avoid
  -- having an unnecessary trailing slash not wanted by the user. Hence the "upstream_url_has_path" check.
  if (not upstream_url_has_path) and (uri:sub(1,1) ~= "/") then
    return "/"..uri
  end
  return uri
end

-- Find an API from a request made to nginx. Either from one of the Host or X-Host-Override headers
-- matching the API's `request_host`, either from the `uri` matching the API's `request_path`.
--
-- To perform this, we need to query _ALL_ APIs in memory. It is the only way to compare the `uri`
-- as a regex to the values set in DB, as well as matching wildcard dns.
-- We keep APIs in the database cache for a longer time than usual.
-- @see https://github.com/Mashape/kong/issues/15 for an improvement on this.
--
-- @param  `uri`          The URI for this request.
-- @return `err`          Any error encountered during the retrieval.
-- @return `api`          The retrieved API, if any.
-- @return `matched_host` The host that was matched for this API, if matched.
-- @return `hosts`        The list of headers values found in Host and X-Host-Override.
-- @return `strip_request_path_pattern` If the API was retrieved by request_path, contain the pattern to strip it from the URI.
local function find_api(uri, headers)
  local api, matched_host, hosts_list, strip_request_path_pattern

  -- Retrieve all APIs
  local apis_dics, err = cache.get_or_set(cache.all_apis_by_dict_key(), _M.load_apis_in_memory)
  if err then
    return err
  end

  -- Find by Host header
  api, matched_host, hosts_list = _M.find_api_by_request_host(headers, apis_dics)
  -- If it was found by Host, return
  if api then
    req_set_header(constants.HEADERS.FORWARDED_HOST, matched_host)
    return nil, api, matched_host, hosts_list, nil
  end

  -- Otherwise, we look for it by request_path. We have to loop over all APIs and compare the requested URI.
  api, strip_request_path_pattern = _M.find_api_by_request_path(uri, apis_dics.request_path_arr)

  return nil, api, nil, hosts_list, strip_request_path_pattern
end

local function url_has_path(url)
  local _, count_slashes = gsub(url, "/", "")
  return count_slashes > 2
end

local function strip_querystring(uri)
  local m, err = re_match(uri, "^(.*)\\?", "oj") -- grab everything before "?"
  if err then
    log(ERR, "[resolver] error stripping querystring from URI: ", err)
  elseif m and m[1] then
    uri = m[1]
  end

  return uri
end

function _M.execute(request_uri, request_headers)
  local uri = strip_querystring(request_uri)
  local err, api, matched_host, hosts_list, strip_request_path_pattern = find_api(uri, request_headers)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  elseif not api then
    return responses.send_HTTP_NOT_FOUND {
      message = "API not found with these values",
      request_host = hosts_list,
      request_path = uri
    }
  end

  local upstream_host
  local upstream_url = api.upstream_url

  -- remove trailing slash because ngx.var.request_uri always starts with a slash
  if sub(upstream_url, -1) == "/" then
    upstream_url = sub(upstream_url, 1, -2)
  end

  -- If API was retrieved by request_path and the request_path needs to be stripped
  if strip_request_path_pattern and api.strip_request_path then
    uri = _M.strip_request_path(uri, strip_request_path_pattern, url_has_path(upstream_url))
    req_set_header(constants.HEADERS.FORWARDED_PREFIX, api.request_path)
  end

  upstream_url = upstream_url..uri

  if api.preserve_host then
    upstream_host = matched_host or req_get_headers()["host"]
  end

  if upstream_host == nil then
    upstream_host = get_host_from_upstream_url(upstream_url)
  end

  return api, upstream_url, upstream_host
end

return _M
