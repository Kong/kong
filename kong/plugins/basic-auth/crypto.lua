---
-- Module to encrypt the basic-auth credentials password field

local utils = require "kong.tools.utils"
local format = string.format

--- Salt the password
-- Password is salted with the credential's consumer_id (long enough, unique)
-- @param credential The basic auth credential table
local function salt_password(credential)
  return format("%s%s", credential.password, credential.consumer_id)
end

local in_openresty = utils.load_module_if_exists("resty.string")
if not in_openresty then
  --- Mock for usage outside of Openresty (unit testing)
  return {encrypt = function(credential)
    local sha1 = require "kong.vendor.sha1"
    local salted = salt_password(credential)
    return sha1(salted)
  end}
end

local resty_sha1 = require "resty.sha1"
local resty_string = require "resty.string"

--- Return a sha1 hash of the given string
-- @param string String (password) to hash
-- @return sha1 hash of the given string
local function sha1(string)
  local sha1 = resty_sha1:new()
  if not sha1 then
    return nil, "failed to create the sha1 object"
  end

  local ok = sha1:update(string)
  if not ok then
    return nil, "failed to add data"
  end

  local digest = sha1:final()
  return resty_string.to_hex(digest)
end

return {
  --- Encrypt the password field credential table
  -- @param credential The basic auth credential table
  -- @return hash of the salted credential's password
  encrypt = function(credential)
    local salted = salt_password(credential)
    return sha1(salted)
  end
}
