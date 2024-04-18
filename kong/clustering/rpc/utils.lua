local _M = {}
local pl_stringx = require("pl.stringx")
local cjson = require("cjson.safe")
local snappy = require("resty.snappy")


local string_sub = string.sub
local assert = assert
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local rfind = pl_stringx.rfind
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
  return err and string_sub(err, -7) == "timeout"
end


function _M.compress_payload(payload)
  local json = assert(cjson_encode(payload))
  return assert(snappy_compress(json))
end


function _M.decompress_payload(compressed)
  local json = assert(snappy_uncompress(compressed))
  return assert(cjson_decode(json))
end


return _M
