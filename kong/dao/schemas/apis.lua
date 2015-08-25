local url = require "socket.url"
local stringy = require "stringy"

local function validate_target_url(value)
  local parsed_url = url.parse(value)
  if parsed_url.scheme and parsed_url.host then
    parsed_url.scheme = parsed_url.scheme:lower()
    if parsed_url.scheme == "http" or parsed_url.scheme == "https" then
      parsed_url.path = parsed_url.path or "/"
      return true, nil, { target_url = url.build(parsed_url)}
    else
      return false, "Supported protocols are HTTP and HTTPS"
    end
  end

  return false, "Invalid target URL"
end

local function check_public_dns_and_path(value, api_t)
  local public_dns = type(api_t.public_dns) == "string" and stringy.strip(api_t.public_dns) or ""
  local path = type(api_t.path) == "string" and stringy.strip(api_t.path) or ""

  if path == "" and public_dns == "" then
    return false, "At least a 'public_dns' or a 'path' must be specified"
  end

  -- Validate wildcard public_dns
  if public_dns then
    local _, count = public_dns:gsub("%*", "")
    if count > 1 then
      return false, "Only one wildcard is allowed: "..public_dns
    elseif count > 0 then
      local pos = public_dns:find("%*")
      local valid
      if pos == 1 then
        valid = public_dns:match("^%*%.") ~= nil
      elseif pos == string.len(public_dns) then
        valid = public_dns:match(".%.%*$") ~= nil
      end

      if not valid then
        return false, "Invalid wildcard placement: "..public_dns
      end
    end
  end
end

local function check_path(path, api_t)
  local valid, err = check_public_dns_and_path(path, api_t)
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
    created_at = { type = "timestamp", dao_insert_value = true, immutable = true },
    name = { type = "string", unique = true, queryable = true, default = function(api_t) return api_t.public_dns end },
    public_dns = { type = "string", unique = true, queryable = true, func = check_public_dns_and_path,
                  regex = "([a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)" },
    path = { type = "string", unique = true, func = check_path },
    strip_path = { type = "boolean" },
    target_url = { type = "string", required = true, func = validate_target_url },
    preserve_host = { type = "boolean" }
  }
}
