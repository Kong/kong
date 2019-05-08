-- Copyright (C) Kong Inc.

local strip = require("pl.stringx").strip
local tonumber = tonumber

local MB = 2^20

local RequestSizeLimitingHandler = {}

RequestSizeLimitingHandler.PRIORITY = 951
RequestSizeLimitingHandler.VERSION = "1.0.0"

local function check_size(length, allowed_size, headers)
  local allowed_bytes_size = allowed_size * MB
  if length > allowed_bytes_size then
    if headers.expect and strip(headers.expect:lower()) == "100-continue" then
      return kong.response.exit(417, { message = "Request size limit exceeded" })
    else
      return kong.response.exit(413, { message = "Request size limit exceeded" })
    end
  end
end

function RequestSizeLimitingHandler:access(conf)
  local headers = kong.request.get_headers()
  local cl = headers["content-length"]

  if cl and tonumber(cl) then
    check_size(tonumber(cl), conf.allowed_payload_size, headers)
  else
    -- If the request body is too big, this could consume too much memory (to check)
    local data = kong.request.get_raw_body()
    if data then
      check_size(#data, conf.allowed_payload_size, headers)
    end
  end
end

return RequestSizeLimitingHandler
