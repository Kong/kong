local kong = kong
local bit = require "bit"
local mac = require "resty.openssl.mac"
local tonumber = tonumber
local ngx = ngx
local type = type
local abs = math.abs
local bor = bit.bor
local bxor = bit.bxor
local byte = string.byte
local gmatch = string.gmatch

local HEADER_WEBHOOK_ID = "webhook-id"
local HEADER_WEBHOOK_SIGN = "webhook-signature"
local HEADER_WEBHOOK_TS = "webhook-timestamp"

local function getHeader(input)
  if type(input) == "table" then
    return input[1]
  end
  
  return input
end

local function sign(secret, id, ts, payload)
  local d, err = mac.new(secret, "HMAC", nil, "sha256")
  if err then
    kong.log.error(err)
    return kong.response.error(500)
  end
  local r, err = d:final(id .. "." .. ts .. "." .. payload)
  if err then
    kong.log.error(err)
    return kong.response.error(500)
  end
  return "v1," .. ngx.encode_base64(r)
end

local function extract_webhook()
  local headers = kong.request.get_headers()

  local id = getHeader(headers[HEADER_WEBHOOK_ID])
  local signature = getHeader(headers[HEADER_WEBHOOK_SIGN])
  local ts = getHeader(headers[HEADER_WEBHOOK_TS])
  if not id or not signature or not ts then
    kong.log.debug("missing required headers")
    return kong.response.error(400)
  end

  ts = tonumber(ts) or 0 -- if parse fails we inject 0, which will fail on clock-skew check

  return id, signature, ts
end


local function constant_time_equals(a, b)
  if #a ~= #b then
    return false
  end

  local diff = 0
  for i = 1, #a do
    diff = bor(diff, bxor(byte(a, i), byte(b, i)))
  end

  return diff == 0
end

-- the header carries a space delimited list during secret rotation
local function signature_matches(header, expected)
  for candidate in gmatch(header, "%S+") do
    if constant_time_equals(candidate, expected) then
      return true
    end
  end

  return false
end

local function access(config)
  local id, signature, ts = extract_webhook()

  if abs(ngx.now() - ts) > config.tolerance_second then
    kong.log.debug("timestamp tolerance exceeded")
    return kong.response.error(400)
  end

  local body = kong.request.get_raw_body()

  if not body or body == "" then
    kong.log.debug("missing required body")
    return kong.response.error(400)
  end

  local expected_signature = sign(config.secret_v1, id, ts, body)

  if not signature_matches(signature, expected_signature) then
    kong.log.debug("signature not matched")
    return kong.response.error(400)
  end
end

return {
  access = access,
  sign = sign
}
