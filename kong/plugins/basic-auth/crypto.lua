-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Module to hash the basic-auth credentials password field
local to_hex = require "resty.string".to_hex
local ngx_null = ngx.null

-- XXX EE
local digest = require "resty.openssl.digest"


--- Salt the password
-- Password is salted with the credential's consumer_id (long enough, unique)
-- @param credential The basic auth credential table
local function salt_password(consumer_id, password)
  if password == nil or password == ngx_null then
    return consumer_id
  end

  return password .. consumer_id
end


return {
  --- Hash the password field credential table
  -- @param credential The basic auth credential table
  -- @return hash of the salted credential's password
  hash = function(consumer_id, password)
    local salted = salt_password(consumer_id, password)
    local sha_hash
    if kong and kong.configuration.fips then
      sha_hash = digest.new("sha256")
    else
      sha_hash = digest.new("sha1")
    end

    local result, err = sha_hash:final(salted)
    if err then
      return nil, err
    end

    return to_hex(result)
  end,

  verify = function(consumer_id, password, expected)
    local salted = salt_password(consumer_id, password)
    local sha_verify
    local fips = kong and kong.configuration.fips
    if fips and expected and #expected == 64 then
      sha_verify = digest.new("sha256")
    else
      if fips then
        kong.log.warn("basic-auth is verifying against SHA1 hashed password, ",
                      "which is disallowed in FIPS mode, key must be updated in this ",
                      "plugin instance to be re-hashed in SHA256")
      end
      sha_verify = digest.new("sha1")
    end

    local result, err = sha_verify:final(salted)
    if err then
      return nil, err
    end

    return to_hex(result) == expected
  end,
}
