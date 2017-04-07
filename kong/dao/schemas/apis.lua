local url = require "socket.url"
local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

local sub = string.sub
local match = string.match

local function validate_upstream_url(value)
  local parsed_url = url.parse(value)
  if parsed_url.scheme and parsed_url.host then
    parsed_url.scheme = parsed_url.scheme:lower()
    if not (parsed_url.scheme == "http" or parsed_url.scheme == "https") then
      return false, "Supported protocols are HTTP and HTTPS"
    end
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
  if hosts then
    for i, host in ipairs(hosts) do
      local ok, err = check_host(host)
      if not ok then
        return false, "host with value '" .. host .. "' is invalid: " .. err
      end
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
  if uris then
    for i, uri in ipairs(uris) do
      local ok, err, trimed_uri = check_uri(uri, api_t.uris)
      if not ok then
        return false, "uri with value '" .. uri .. "' is invalid: " .. err
      end

      if trimed_uri then
        api_t.uris[i] = trimed_uri
      end
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
  if methods then
    for i, method in ipairs(methods) do
      local ok, err = check_method(method)
      if not ok then
        return false, "method with value '" .. method .. "' is invalid: " .. err
      end
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
local function check_smallint(i)
  -- Postgres 'smallint' size, 2 bytes
  if i < 0 or math.floor(i) ~= i or i > 32767 then
    return false, "must be an integer between 0 and 32767"
  end

  return true
end

local function check_u_int(t)
  if t < 1 or t > 2^31 - 1 or math.floor(t) ~= t then
    return false, "must be an integer between 1 and " .. 2^31 - 1
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
    hosts = {type = "array", func = check_hosts},
    uris = {type = "array", func = check_uris},
    methods = {type = "array", func = check_methods},
    strip_uri = {type = "boolean", default = true},
    https_only = {type = "boolean", default = false},
    http_if_terminated = {type = "boolean", default = true},
    upstream_url = {type = "url", required = true, func = validate_upstream_url},
    preserve_host = {type = "boolean", default = false},
    retries = {type = "number", default = 5, func = check_smallint},
    upstream_connect_timeout = {type = "number", default = 60000, func = check_u_int},
    upstream_send_timeout = {type = "number", default = 60000, func = check_u_int},
    upstream_read_timeout = {type = "number", default = 60000, func = check_u_int},
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end,
  self_check = function(schema, api_t, dao, is_update)
    if is_update then
      return true
    end

    local ok

    for _, name in ipairs({"uris", "hosts", "methods" }) do
      local v = api_t[name]

      if v ~= nil and #v > 0 then
        ok = true
        break
      end
    end

    if not ok then
      return false, Errors.schema "at least one of 'hosts', 'uris' or 'methods' must be specified"
    end

    return true
  end
}
