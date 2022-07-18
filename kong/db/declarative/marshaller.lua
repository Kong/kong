-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
