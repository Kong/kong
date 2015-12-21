-- Module to encrypt the basic-auth credentials password field

local crypto = require "crypto"
local format = string.format

--- Salt the password
-- Password is salted with the credential's consumer_id (long enough, unique)
-- @param credential The basic auth credential table
local function salt_password(credential)
  return format("%s%s", credential.password, credential.consumer_id)
end

return {
  --- Encrypt the password field credential table
  -- @param credential The basic auth credential table
  -- @return hash of the salted credential's password
  encrypt = function(credential)
    local salted = salt_password(credential)
    return crypto.digest("sha1", salted)
  end
}
