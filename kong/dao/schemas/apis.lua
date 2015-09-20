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

local function check_inbound_dns_and_path(value, api_t)
  local inbound_dns = type(api_t.inbound_dns) == "string" and stringy.strip(api_t.inbound_dns) or ""
  local path = type(api_t.path) == "string" and stringy.strip(api_t.path) or ""

  if path == "" and inbound_dns == "" then
    return false, "At least an 'inbound_dns' or a 'path' must be specified"
  end

  -- Validate wildcard inbound_dns
  if inbound_dns then
    local _, count = inbound_dns:gsub("%*", "")
    if count > 1 then
      return false, "Only one wildcard is allowed: "..inbound_dns
    elseif count > 0 then
      local pos = inbound_dns:find("%*")
      local valid
      if pos == 1 then
        valid = inbound_dns:match("^%*%.") ~= nil
      elseif pos == string.len(inbound_dns) then
        valid = inbound_dns:match(".%.%*$") ~= nil
      end

      if not valid then
        return false, "Invalid wildcard placement: "..inbound_dns
      end
    end
  end
end

local function check_path(path, api_t)
  local valid, err = check_inbound_dns_and_path(path, api_t)
  if valid == false then
    return false, err
  end

  if path then
    path = string.gsub(path, "^/*", "")
    path = string.gsub(path, "/*$", "")

    -- Add a leading slash for the sake of consistency
    api_t.path = "/"..path

    -- Check if characters are in RFC 3986 unreserved list
    local is_alphanumeric = string.match(api_t.path, "^/[%w%.%-%_~%/]*$")
    if not is_alphanumeric then
      return false, "path must only contain alphanumeric and '. -, _, ~, /' characters"
    end
    local is_invalid = string.match(api_t.path, "//+")
    if is_invalid then
      return false, "path is invalid: "..api_t.path
    end
  end

  return true
end

return {
  name = "API",
  primary_key = {"id"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    name = { type = "string", unique = true, queryable = true, default = function(api_t) return api_t.inbound_dns end },
    inbound_dns = { type = "string", unique = true, queryable = true, func = check_inbound_dns_and_path,
                  regex = "([a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)" },
    path = { type = "string", unique = true, func = check_path },
    strip_path = { type = "boolean" },
    upstream_url = { type = "url", required = true, func = validate_upstream_url_protocol },
    preserve_host = { type = "boolean" }
  }
}
