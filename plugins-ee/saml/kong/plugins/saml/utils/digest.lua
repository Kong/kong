
-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx               = ngx
local base64_decode     = ngx.decode_base64

local _M = {}

local generate = {
  SHA256 = function(data)
    local sha256 = (require "resty.sha256").new()
    sha256:update(data)
    return sha256:final()
  end,
  SHA384 = function(data)
    local sha384 = (require "resty.sha384").new()
    sha384:update(data)
    return sha384:final()
  end,
  SHA512 = function(data)
    local sha512 = (require "resty.sha512").new()
    sha512:update(data)
    return sha512:final()
  end,
  SHA1 = function(data)
    local sha1 = (require "resty.sha1").new()
    sha1:update(data)
    return sha1:final()
  end,
}

function _M.verify(data, dv, alg)
  return generate[alg](data) == base64_decode(dv)
end

function _M.generate(data, alg)
  return generate[alg](data)
end

return _M
