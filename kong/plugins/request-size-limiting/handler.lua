-- Copyright (C) Kong Inc.

local strip = require("kong.tools.string").strip
local kong_meta = require "kong.meta"
local tonumber = tonumber
local lfs = require "lfs"


local RequestSizeLimitingHandler = {}

RequestSizeLimitingHandler.PRIORITY = 951
RequestSizeLimitingHandler.VERSION = kong_meta.version


local size_units = {
  "megabytes",
  "kilobytes",
  "bytes",
}
RequestSizeLimitingHandler.size_units = size_units


local unit_multiplication_factor = {
  ["bytes"]        = 1,
  ["kilobytes"]    = 1024,    -- 2 ^ 10 bytes
  ["megabytes"]    = 1048576, -- 2 ^ 20 bytes
}
RequestSizeLimitingHandler.unit_multiplication_factor = unit_multiplication_factor


local function check_size(length, allowed_size, headers, unit)
  local allowed_bytes_size = allowed_size * unit_multiplication_factor[unit]
  if length > allowed_bytes_size then
    if headers.expect and strip(headers.expect:lower()) == "100-continue" then
      return kong.response.error(417, "Request size limit exceeded")
    else
      return kong.response.error(413, "Request size limit exceeded")
    end
  end
end

function RequestSizeLimitingHandler:access(conf)
  local headers = kong.request.get_headers()
  local cl = headers["content-length"]

  if cl and tonumber(cl) then
    check_size(tonumber(cl), conf.allowed_payload_size, headers, conf.size_unit)
  else
    if conf.require_content_length and headers["Transfer-Encoding"] ~= "chunked" then
      return kong.response.error(411, "A valid Content-Length header is required")
    end
    -- If the request body is too big, this could consume too much memory (to check)
    local data = kong.request.get_raw_body()
    if data then
      check_size(#data, conf.allowed_payload_size, headers, conf.size_unit)
    else
      -- Check the file size when the request body buffered to a temporary file
      local body_filepath = ngx.req.get_body_file()
      if body_filepath then
        local file_size = lfs.attributes(body_filepath, "size")
        check_size(file_size, conf.allowed_payload_size, headers, conf.size_unit)
      else 
        kong.log.warn("missing request body")
      end
    end
  end
end

return RequestSizeLimitingHandler
