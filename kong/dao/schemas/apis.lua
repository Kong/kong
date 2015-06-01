local url = require "socket.url"
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

return {
  id = { type = constants.DATABASE_TYPES.ID },
  name = { type = "string", unique = true, queryable = true, default = function(api_t) return api_t.public_dns end },
  public_dns = { type = "string", required = true, unique = true, queryable = true,
                 regex = "([a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)" },
  path = { type = "string", queryable = true, unique = true },
  target_url = { type = "string", required = true, func = validate_target_url },
  created_at = { type = constants.DATABASE_TYPES.TIMESTAMP }
}
