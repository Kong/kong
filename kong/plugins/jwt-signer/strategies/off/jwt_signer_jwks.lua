-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local cache = require "kong.plugins.jwt-signer.cache"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local table_insert = table.insert
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy

local jwt_signer_jwks = {}

function jwt_signer_jwks:page(size, offset, options)

  if not size then
    size = self.connector:get_page_size(options)
  end

  if offset then
    local token = decode_base64(offset)
    if not token then
      return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
    end

    local number = tonumber(token)
    if not number then
      return nil, self.errors:invalid_offset(offset, "invalid offset")
    end

    offset = number
  else
    offset = 1
  end

  local keys = cache.get_all_keys()
  local jwks = {}

  for _, value in pairs(keys) do
    table_insert(jwks, value)
  end

  local records, index, total = {}, 1, #jwks
  if total == 0 then
    return records
  end

  for i = offset, offset + size - 1 do
    records[index] = jwks[i]
    if i == total then
      offset = nil
      break
    end
    index = index + 1
  end

  if offset then
    return records, nil, nil, encode_base64(tostring(offset + size), true)
  end

  return records
end

function jwt_signer_jwks.select_by_name(_, name)
  return cycle_aware_deep_copy(cache.get_keys(name))
end

return jwt_signer_jwks
