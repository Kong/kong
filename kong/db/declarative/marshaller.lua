local buffer = require "string.buffer"


local encode = buffer.encode
local decode = buffer.decode


local _M = {}


function _M.marshall(value)
  if value == nil then
    return nil
  end

  value = encode(value)

  return value
end


function _M.unmarshall(value, err)
  if value == nil or err then
    -- this allows error/nil propagation in deserializing value from LMDB
    return nil, err
  end

  value = decode(value)

  return value
end


return _M
