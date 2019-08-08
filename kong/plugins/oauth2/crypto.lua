-- Module to hash the basic-auth credentials password field
local sha256 = require "resty.sha256"
local to_hex = require "resty.string".to_hex
local resty_random = require "resty.random"
local assert = assert


local function hash_secret_with_salt(client_secret, salt)
  if client_secret == nil or client_secret == ngx.null then
    client_secret = ""
  end

  local salted = client_secret .. salt
  local digest = sha256:new()
  assert(digest:update(salted))
  return to_hex(digest:final())
end

return {
  hash = function(secret)
    local salt = to_hex(resty_random.bytes(16))
    return hash_secret_with_salt(secret, salt), salt
  end,

  validate = function(secret, hashed_secret, salt)
    return hashed_secret == hash_secret_with_salt(secret, salt)
  end
}
