-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local bytes   = require "resty.openssl.rand".bytes
local codec   = require "kong.openid-connect.codec"
local hash    = require "kong.openid-connect.hash"


local concat = table.concat
local type   = type
local sub    = string.sub


return function(len, hsh, cdc)
  len = len or 16

  local err
  local rnd = bytes(len)

  if hsh then
    if type(hsh) == "string" then
      hsh = hash[hsh]
    end
    if type(hsh) == "function" then
      local i, ln, hs = 1, 0, {}

      repeat
        hs[i] = hsh(rnd)
        ln = ln + #hs[i]
        i = i + 1
      until ln >= len

      rnd = concat(hs)

      if ln > len then
        rnd = sub(rnd, 1, len)
      end
    end
  end

  if cdc then
    if type(cdc) == "string" then
      if codec[cdc] then
        cdc = codec[cdc].encode
      end
    end
    if type(cdc) == "function" then
      rnd, err = cdc(rnd)
      if not rnd then
        return nil, err
      end
    end
  end

  return rnd
end

