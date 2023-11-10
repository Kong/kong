local cjson = require("cjson.safe")
local gzip = require("kong.tools.gzip")


local assert = assert


local compress   = gzip.deflate_gzip
local uncompress = gzip.inflate_gzip


local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local BIG_DATA_LEN = 8 * 1024


local _M = {}


local yield --= utils.yield
do
  local ngx_sleep = _G.native_ngx_sleep or ngx.sleep

  yield = function()
    ngx_sleep(0)  -- yield
  end
end


-- TODO: error check
function _M.encode(obj)
  local data = assert(cjson_encode(obj))

  local is_big = #data > BIG_DATA_LEN
  if is_big then
    yield()
  end

  data = assert(compress(data))
  if is_big then
    yield()
  end

  return data
  --return cjson_encode(obj)
end


-- TODO: error check
function _M.decode(data)
  local data = assert(uncompress(data))

  local is_big = #data > BIG_DATA_LEN
  if is_big then
    yield()
  end

  local obj = assert(cjson_decode(data))

  if is_big then
    yield()
  end

  return obj
  --return cjson_decode(data)
end


return _M
