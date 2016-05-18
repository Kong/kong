local url = require "socket.url"
local stringy = require "stringy"

local fmt = string.format
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

local function check_request_host_and_path(api_t)
  local request_host = type(api_t.request_host) == "string" and stringy.strip(api_t.request_host) or ""
  local request_path = type(api_t.request_path) == "string" and stringy.strip(api_t.request_path) or ""

  if request_path == "" and request_host == "" then
    return false, "At least a 'request_host' or a 'request_path' must be specified"
  end

  return true
end

local host_allowed_chars = "[%d%a%-%.%_]"
local ext_allowed_chars = "[%d%a]"
local dns_pattern = "^"..host_allowed_chars.."+%."..ext_allowed_chars..ext_allowed_chars.."+$"

local function check_request_host(request_host, api_t)
  local valid, err = check_request_host_and_path(api_t)
  if valid == false then
    return false, err
  end

  if request_host ~= nil and request_host ~= "" then
    local _, count = request_host:gsub("%*", "")
    if count == 0 then
      -- Validate regular request_host
      local match = request_host:match(dns_pattern)
      if match == nil then
        return false, "Invalid value: "..request_host
      end

      -- Reject prefix/trailing dashes and dots in each segment
      for _, segment in ipairs(stringy.split(request_host, ".")) do
        if segment == "" or segment:match("^-") or segment:match("-$") or segment:match("^%.") or segment:match("%.$") then
          return false, "Invalid value: "..request_host
        end
      end
    elseif count == 1 then
      -- Validate wildcard request_host
      local valid
      local pos = request_host:find("%*")
      if pos == 1 then
        valid = request_host:match("^%*%.") ~= nil
      elseif pos == string.len(request_host) then
        valid = request_host:match(".%.%*$") ~= nil
      end

      if not valid then
        return false, "Invalid wildcard placement: "..request_host
      end
    else
      return false, "Only one wildcard is allowed: "..request_host
    end
  end

  return true
end

local function check_request_path(request_path, api_t)
  local valid, err = check_request_host_and_path(api_t)
  if valid == false then
    return false, err
  end

  if request_path ~= nil and request_path ~= "" then
    if sub(request_path, 1, 1) ~= "/" then
      return false, fmt("must be prefixed with slash: '%s'", request_path)
    elseif match(request_path, "//+") then
      -- Check for empty segments (/status//123)
      return false, fmt("invalid: '%s'", request_path)
    elseif not match(request_path, "^/[%w%.%-%_~%/]*$") then
      -- Check if characters are in RFC 3986 unreserved list
      return false, "must only contain alphanumeric and '., -, _, ~, /' characters"
    end

    -- From now on, the request_path is considered valid.
    -- Remove trailing slash
    if request_path ~= "/" and sub(request_path, -1) == "/" then
      api_t.request_path = sub(request_path, 1, -2)
    end
  end

  return true
end

--- Define a default name for an API.
-- Chosen from request_host or request_path (in that order of preference) if they are set.
-- Normalize the name if it contains any characters from RFC 3986 reserved list.
-- @see https://tools.ietf.org/html/rfc3986#section-2.2
-- @param api_t Table representing the API
-- @return default_name Serialized chosen name or nil
local function default_name(api_t)
  local default_name, err, _

  default_name = api_t.request_host
  if default_name == nil and api_t.request_path ~= nil then
    default_name = api_t.request_path:sub(2):gsub("/", "-")
  end

  if default_name ~= nil then
    default_name, _, err = ngx.re.gsub(default_name, "[^\\w.\\-_~]", "-")
    if err then
      ngx.log(ngx.ERR, err)
      return
    end

    return default_name
  end
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

return {
  table = "apis",
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true, required = true},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true, required = true},
    name = {type = "string", unique = true, default = default_name, func = check_name},
    request_host = {type = "string", unique = true, func = check_request_host},
    request_path = {type = "string", unique = true, func = check_request_path},
    strip_request_path = {type = "boolean", default = false},
    upstream_url = {type = "url", required = true, func = validate_upstream_url_protocol},
    preserve_host = {type = "boolean", default = false}
  },
  marshall_event = function(self, t)
    return { id = t.id }
  end
}
