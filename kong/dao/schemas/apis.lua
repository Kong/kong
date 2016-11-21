local url = require "socket.url"
local utils = require "kong.tools.utils"

local sub = string.sub
local match = string.match

local function validate_upstream_url_protocol(value)
  local parsed_url = url.parse(value)
  if parsed_url.scheme and parsed_url.host then
    parsed_url.scheme = parsed_url.scheme:lower()
    if not (parsed_url.scheme == "http" or parsed_url.scheme == "https") then
      return false, "Supported protocols are HTTP and HTTPS"
    end
  end

  return true
end

local required_properties = { "uris", "hosts", "methods" }

local function check_hosts_uris_methods(api_t)
  local ok

  for _, name in ipairs(required_properties) do
    local v = api_t[name]

    if v ~= nil and #v > 0 then
      ok = true
    end
  end

  if not ok then
    return false, "at least one of 'hosts', 'uris' or 'methods' must be specified"
  end

  return true
end

local function check_host(host)
  if type(host) ~= "string" then
    return false, "must be a string"

  elseif utils.strip(host) == "" then
    return false, "host is empty"
  end

  local temp, count = host:gsub("%*", "abc")  -- insert valid placeholder for verification

  -- Validate regular request_host
  local normalized = utils.normalize_ip(temp)
  if (not normalized) or normalized.port then
    return false, "Invalid hostname"
  end

  if count == 1 then
    -- Validate wildcard request_host
    local valid
    local pos = host:find("%*")
    if pos == 1 then
      valid = host:match("^%*%.") ~= nil

    elseif pos == #host then
      valid = host:match(".%.%*$") ~= nil
    end

    if not valid then
      return false, "Invalid wildcard placement"
    end

  elseif count > 1 then
    return false, "Only one wildcard is allowed"
  end

  return true
end

local function check_hosts(hosts, api_t)
  if type(hosts) ~= "table" then
    return false, "not an array"
  end

  local ok, err = check_hosts_uris_methods(api_t)
  if not ok then
    return false, err
  end

  for i, host in ipairs(hosts) do
    local ok, err = check_host(host)
    if not ok then
      return false, "host with value '" .. host .. "' is invalid: " .. err
    end
  end

  return true
end

local function check_uri(uri)
  if type(uri) ~= "string" then
    return false, "must be a string"

  elseif utils.strip(uri) == "" then
    return false, "uri is empty"

  elseif sub(uri, 1, 1) ~= "/" then
    return false, "must be prefixed with slash"

  elseif match(uri, "//+") then
    -- Check for empty segments (/status//123)
    return false, "invalid"

  elseif not match(uri, "^/[%w%.%-%_~%/%%]*$") then
    -- Check if characters are in RFC 3986 unreserved list, and % for percent encoding
    return false, "must only contain alphanumeric and '., -, _, ~, /, %' characters"
  end

  local esc = uri:gsub("%%%x%x", "___") -- drop all proper %-encodings
  if match(esc, "%%") then
    -- % is remaining, so not properly encoded
    local err = uri:sub(esc:find("%%.?.?"))
    return false, "must use proper encoding; '"..err.."' is invalid"
  end

  -- From now on, the request_path is considered valid.
  -- Remove trailing slash
  if uri ~= "/" and sub(uri, -1) == "/" then
    uri = sub(uri, 1, -2)
  end

  return true, nil, uri
end

local function check_uris(uris, api_t)
  if type(uris) ~= "table" then
    return false, "not an array"
  end

  local ok, err = check_hosts_uris_methods(api_t)
  if not ok then
    return false, err
  end

  for i, uri in ipairs(uris) do
    local ok, err, trimed_uri = check_uri(uri, api_t.uris)
    if not ok then
      return false, "uri with value '" .. uri .. "' is invalid: " .. err
    end

    if trimed_uri then
      api_t.uris[i] = trimed_uri
    end
  end

  return true
end

local function check_method(method)
  if type(method) ~= "string" then
    return false, "must be a string"

  elseif utils.strip(method) == "" then
    return false, "method is empty"

  elseif not match(method, "^%u+$") then
    return false, "invalid value"
  end

  return true
end

local function check_methods(methods, api_t)
  if type(methods) ~= "table" then
    return false, "not an array"
  end

  local ok, err = check_hosts_uris_methods(api_t)
  if not ok then
    return false, err
  end

  for i, method in ipairs(methods) do
    local ok, err = check_method(method)
    if not ok then
      return false, "method with value '" .. method .. "' is invalid: " .. err
    end
  end

  return true
end

--- Check that a name is valid for an API.
-- It must not contain any URI reserved characters.
-- @param name Name of the API.
-- @return valid Boolean indicating if valid or not.
-- @return err String describing why the name is not valid.
local function check_name(name)
  if name then
    local m, err = ngx.re.match(name, "[^\\w.\\-_~]")
    if err then
      ngx.log(ngx.ERR, err)
      return

    elseif m then
      return false, "name must only contain alphanumeric and '., -, _, ~' characters"
    end
  end

  return true
end

-- check that retries is a valid number
local function check_retries(retries)
  -- Postgres 'smallint' size, 2 bytes
  if (retries < 0) or (math.floor(retries) ~= retries) or (retries > 32767) then
    return false, "retries must be an integer, from 0 to 32767"
  end
  return true
end

return {
  table = "apis",
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true, required = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true, required = true},
    name = {type = "string", unique = true, required = true, func = check_name},
    --request_host = {type = "string", unique = true, func = check_request_host},
    --request_path = {type = "string", unique = true, func = check_request_path},

    hosts = {type = "array", default = {}, func = check_hosts},
    uris = {type = "array", default = {}, func = check_uris},
    methods = {type = "array", default = {}, func = check_methods},

    strip_request_path = {type = "boolean", default = false},
    upstream_url = {type = "url", required = true, func = validate_upstream_url_protocol},
    preserve_host = {type = "boolean", default = false},
    retries = {type = "number", default = 5, func = check_retries},
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
