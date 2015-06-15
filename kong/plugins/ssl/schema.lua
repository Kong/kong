local ssl_util = require "kong.plugins.ssl.ssl_util"
local base64 = require "base64"

local function validate_cert(v)
  local der = ssl_util.cert_to_der(v)
  if der then
    return true, nil, { _cert_der_cache = base64.encode(der) }
  end
  return false, "Invalid data"
end

local function validate_key(v)
  local der = ssl_util.key_to_der(v)
  if der then
    return true, nil, { _key_der_cache = base64.encode(der) }
  end
  return false, "Invalid data"
end

return {
  fields = {
    cert = { required = true, type = "string", func = validate_cert },
    key = { required = true, type = "string", func = validate_key },
    only_https = { required = false, type = "boolean", default = false },

    -- Internal use
    _cert_der_cache = { type = "string", immutable = true },
    _key_der_cache = { type = "string", immutable = true }
  }
}
