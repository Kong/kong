local kong = kong

local fmt = string.format


local _M = {}

_M.off = true

function _M:select_ids_by_key(key)
  local cred, _ = kong.db.keyauth_enc_credentials:select_by_key(key)
  return cred and { { id = cred.id } } or {}
end


return _M
