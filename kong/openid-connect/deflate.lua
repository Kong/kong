-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local zlib   = require "ffi-zlib"
local sio    = require "pl.stringio"


local concat = table.concat


local function gzip(func, input)
  local stream = sio.open(input)
  local output = {}
  local n = 0

  local ok, err = func(function(size)
    return stream:read(size)
  end, function(data)
    n = n + 1
    output[n] = data
  end, 8192, -15) -- 8kb chunk size, -15 = raw deflate

  if not ok then
    return nil, err
  end

  if n == 0 then
    return ""
  end

  return concat(output, nil, 1, n)
end


local deflate = {}


function deflate.compress(data)
  return gzip(zlib.deflateGzip, data)
end


function deflate.decompress(data)
  return gzip(zlib.inflateGzip, data)
end


return deflate
