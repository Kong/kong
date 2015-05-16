local ssl_util = require "kong.plugins.ssl.ssl_util"
local base64 = require "base64"

local function validate_cert(v)
  local der = ssl_util.cert_to_der(v)
  if der then
    return true, nil, { cert_der = base64.encode(der) }
  end
  return false, "Invalid data"
end

local function validate_key(v)
  local der = ssl_util.key_to_der(v)
  if der then
    return true, nil, { key_der = base64.encode(der) }
  end
  return false, "Invalid data"
end

return {
  cert = { required = true, type = "string", func = validate_cert },
  key = { required = true, type = "string", func = validate_key },
  only_ssl = { required = false, type = "boolean", default = false },

  -- Internal use
  cert_der = { type = "string", immutable = true },
  key_der = { type = "string", immutable = true }
}
