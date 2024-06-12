-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local cjson = require("cjson")
local snappy = require("resty.snappy")


local string_sub = string.sub
local assert = assert
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local rfind = require("pl.stringx").rfind
local snappy_compress = snappy.compress
local snappy_uncompress = snappy.uncompress


function _M.parse_method_name(method)
  local pos = rfind(method, ".")
  if not pos then
    return nil, "not a valid method name"
  end

  return method:sub(1, pos - 1), method:sub(pos + 1)
end


function _M.is_timeout(err)
  return err and (err == "timeout" or string_sub(err, -7) == "timeout")
end


function _M.compress_payload(payload)
  local json = cjson_encode(payload)
  local data = assert(snappy_compress(json))
  return data
end


function _M.decompress_payload(compressed)
  local json = assert(snappy_uncompress(compressed))
  local data = cjson_decode(json)
  return data
end


return _M
