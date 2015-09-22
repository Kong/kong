local url = require "socket.url"
local stringy = require "stringy"

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

local function check_request_host_and_path(value, api_t)
  local request_host = type(api_t.request_host) == "string" and stringy.strip(api_t.request_host) or ""
  local request_path = type(api_t.request_path) == "string" and stringy.strip(api_t.request_path) or ""

  if request_path == "" and request_host == "" then
    return false, "At least a 'request_host' or a 'request_path' must be specified"
  end

  -- Validate wildcard request_host
  if request_host then
    local _, count = request_host:gsub("%*", "")
    if count > 1 then
      return false, "Only one wildcard is allowed: "..request_host
    elseif count > 0 then
      local pos = request_host:find("%*")
      local valid
      if pos == 1 then
        valid = request_host:match("^%*%.") ~= nil
      elseif pos == string.len(request_host) then
        valid = request_host:match(".%.%*$") ~= nil
      end

      if not valid then
        return false, "Invalid wildcard placement: "..request_host
      end
    end
  end
end

local function check_request_path(request_path, api_t)
  local valid, err = check_request_host_and_path(request_path, api_t)
  if valid == false then
    return false, err
  end

  if request_path then
    request_path = string.gsub(request_path, "^/*", "")
    request_path = string.gsub(request_path, "/*$", "")

    -- Add a leading slash for the sake of consistency
    api_t.request_path = "/"..request_path

    -- Check if characters are in RFC 3986 unreserved list
    local is_alphanumeric = string.match(api_t.request_path, "^/[%w%.%-%_~%/]*$")
    if not is_alphanumeric then
      return false, "request_path must only contain alphanumeric and '., -, _, ~, /' characters"
    end
    local is_invalid = string.match(api_t.request_path, "//+")
    if is_invalid then
      return false, "request_path is invalid: "..api_t.request_path
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
  local default_name, err

  default_name = api_t.request_host
  if not default_name and api_t.request_path then
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
    end

    if m then
      return false, "name must only contain alphanumeric and '., -, _, ~' characters"
    end
  end

  return true
end

return {
  name = "API",
  primary_key = {"id"},
  fields = {
    id = {type = "id", dao_insert_value = true},
    created_at = {type = "timestamp", dao_insert_value = true},
    name = {type = "string", unique = true, queryable = true, default = default_name, func = check_name},
    request_host = {type = "string", unique = true, queryable = true, func = check_request_host_and_path,
                  regex = "([a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)"},
    request_path = {type = "string", unique = true, func = check_request_path},
    strip_request_path = {type = "boolean"},
    upstream_url = {type = "url", required = true, func = validate_upstream_url_protocol},
    preserve_host = {type = "boolean"}
  }
}
