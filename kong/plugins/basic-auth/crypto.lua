-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Module to hash the basic-auth credentials password field
local sha1 = require "resty.sha1"
local to_hex = require "resty.string".to_hex
local assert = assert


--- Salt the password
-- Password is salted with the credential's consumer_id (long enough, unique)
-- @param credential The basic auth credential table
local function salt_password(consumer_id, password)
  if password == nil or password == ngx.null then
    password = ""
  end

  return password .. consumer_id
end


return {
  --- Hash the password field credential table
  -- @param credential The basic auth credential table
  -- @return hash of the salted credential's password
  hash = function(consumer_id, password)
    local salted = salt_password(consumer_id, password)
    local digest = sha1:new()
    assert(digest:update(salted))
    return to_hex(digest:final())
  end
}
