local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")


local deflate_gzip = utils.deflate_gzip
local inflate_gzip = utils.inflate_gzip
local yield = utils.yield


local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local BIG_DATA_LEN = 8 * 1024


local _M = {}


-- TODO: error check
function _M.encode(obj)
  local data = cjson_encode(obj)

  local is_big = #data > BIG_DATA_LEN
  if is_big then
    yield()
  end

  data = deflate_gzip(data)
  if is_big then
    yield()
  end

  return data
  --return cjson_encode(obj)
end


-- TODO: error check
function _M.decode(data)
  local data = inflate_gzip(data)

  local is_big = #data > BIG_DATA_LEN
  if is_big then
    yield()
  end

  local obj = cjson_decode(data)

  if is_big then
    yield()
  end

  return obj
  --return cjson_decode(data)
end


return _M
