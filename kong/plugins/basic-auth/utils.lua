local resty_string = require "resty.string"
local resty_sha1 = require "resty.sha1"

local string_format = string.format

_M = {}

-- sha1 — Calculate the sha1 hash of a string
-- @param `string` input string.
-- @return `string` the sha1 of the given string.
function _M.sha1(string)
  local sha1 = resty_sha1:new()
  if not sha1 then
    return nil, "failed to create the sha1 object"
  end

  local ok = sha1:update(string)
  if not ok then
    return nil, "failed to add data"
  end

  local digest = sha1:final()  -- binary digest
  return resty_string.to_hex(digest)
end

function _M.salt_credentials(credential)
  return string_format("%s:%s", credential.password, credential.consumer_id)
end

-- transformation table for all supported encryption mathods.
_M.encryption_methods = {
  plain = function(credential) return credential.password end,
  sha1 = function(credential)
    local password_salted = _M.salt_credentials(credential)
    ngx.log(ngx.ERR, "Dalted: ", password_salted)
    return _M.sha1(password_salted)
  end,
}

return _M