-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local codec        = require "kong.openid-connect.codec"
local jws          = require "kong.openid-connect.jws"
local jwe          = require "kong.openid-connect.jwe"
local nyi          = require "kong.openid-connect.nyi"


local setmetatable = setmetatable
local base64url    = codec.base64url
local json         = codec.json
local find         = string.find
local type         = type
local sub          = string.sub


local function split(jwt)
  local t = {}
  local i = 1
  local b = 1
  local e = find(jwt, ".", b, true)
  while e do
    t[i] = sub(jwt, b, e - 1)
    i = i + 1
    b = e + 1
    e = find(jwt, ".", b, true)
  end
  t[i] = sub(jwt, b)
  return t, i
end


local jwt = {}


jwt.__index = jwt


function jwt.new(oic)
  return setmetatable({ oic = oic }, jwt)
end


function jwt.type(input)
  if type(input) ~= "string" then
    return nil
  end
  local i = 1
  local b = 1
  local e = find(input, ".", b, true)
  while e do
    local decoded = base64url.decode(sub(input, b, e - 1))
    if not decoded then
      return nil
    end
    if b == 1 then
      local ok = json.decode(decoded)
      if not ok then
        return nil
      end
    end
    i = i + 1
    b = e + 1
    e = find(input, ".", b, true)
  end
  if i == 3 then
    return "JWS"
  elseif i == 5 then
    return "JWE"
  end
end


function jwt:encode()
  return nyi(self)
end


function jwt:decode(input, options)
  local parts, pz = split(input)

  if pz == 3 then
    return jws.decode(parts, options, self.oic)

  elseif pz == 5 then
    return jwe.decode(parts, options, self.oic)
  end

  return nyi()
end


function jwt:decode_dpop_proof(input, options)
  local parts, pz = split(input)

  if pz == 3 then
    local decoded, err = jws.decode(parts, options, self.oic, true)
    if not decoded then
      return nil, err
    end
    if type(decoded.payload) ~= "table" then
      return nil, "invalid DPoP payload"
    end
    return decoded
  end

  return nil, "invalid DPoP proof"
end


return jwt
