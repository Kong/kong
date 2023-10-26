local cjson = require("cjson.safe")


local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {}


function _M.encode(obj)
  return cjson_encode(obj)
end


function _M.decode(data)
  return cjson_decode(data)
end


return _M
