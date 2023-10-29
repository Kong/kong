local cjson = require("cjson.safe")
local utils = require("kong.tools.utils")


local compress   = utils.deflate_gzip
local uncompress = utils.inflate_gzip


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
  local data = cjson_encode(obj)

  local is_big = #data > BIG_DATA_LEN
  if is_big then
    yield()
  end

  data = compress(data)
  if is_big then
    yield()
  end

  return data
  --return cjson_encode(obj)
end


-- TODO: error check
function _M.decode(data)
  local data = uncompress(data)

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
