-- Module to hash the basic-auth credentials password field
local sha1 = require "resty.sha1"
local to_hex = require "resty.string".to_hex
local assert = assert


--- Salt the password
-- Password is salted with the credential's kongsumer_id (long enough, unique)
-- @param credential The basic auth credential table
local function salt_password(kongsumer_id, password)
  if password == nil or password == ngx.null then
    password = ""
  end

  return password .. kongsumer_id
end


return {
  --- Hash the password field credential table
  -- @param credential The basic auth credential table
  -- @return hash of the salted credential's password
  hash = function(kongsumer_id, password)
    local salted = salt_password(kongsumer_id, password)
    local digest = sha1:new()
    assert(digest:update(salted))
    return to_hex(digest:final())
  end
}
