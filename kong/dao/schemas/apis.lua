local url = require "socket.url"
local stringy = require "stringy"
local constants = require "kong.constants"

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

  return true
end

local function check_path(path, api_t)
  local valid, err = check_public_dns_and_path(path, api_t)
  if not valid then
    return false, err
  end

  if path then
    -- Prefix with `/` for the sake of consistency
    local has_slash = string.match(path, "^/")
    if not has_slash then api_t.path = "/"..path end
    -- Check if characters are in RFC 3986 unreserved list
    local is_alphanumeric = string.match(api_t.path, "^/[%w%.%-%_~]*/?$")
    if not is_alphanumeric then
      return false, "path must only contain alphanumeric and '. -, _, ~' characters"
    end
  end

  return true
end

return {
  id = { type = constants.DATABASE_TYPES.ID },
  name = { type = "string", unique = true, queryable = true, default = function(api_t) return api_t.public_dns end },
  public_dns = { type = "string", unique = true, queryable = true,
                func = check_public_dns_and_path,
                regex = "([a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)" },
  path = { type = "string", queryable = true, unique = true, func = check_path },
  strip_path = { type = "boolean" },
  target_url = { type = "string", required = true, func = validate_target_url },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}
