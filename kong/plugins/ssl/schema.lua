local ssl_util = require "kong.plugins.ssl.ssl_util"
local base64 = require "base64"

local function validate_cert(v)
  local der, err = ssl_util.cert_to_der(v)
  if der then
    return true, nil, { _cert_der_cache = base64.encode(der) }
  end
  return false, "Invalid data: "..err
end

local function validate_key(v)
  local der, err = ssl_util.key_to_der(v)
  if der then
    return true, nil, { _key_der_cache = base64.encode(der) }
  end
  return false, "Invalid data: "..err
end

return {
  no_consumer = true,
  fields = {
    cert = { required = true, type = "string", func = validate_cert },
    key = { required = true, type = "string", func = validate_key },
    only_https = { required = false, type = "boolean", default = false },
    accept_http_if_already_terminated = { required = false, type = "boolean", default = false },

    -- Internal use
    _cert_der_cache = { type = "string" },
    _key_der_cache = { type = "string" }
  },
  marshall_event = function(self, t)
    return {} -- We don't need any value in the cache event
  end
}
