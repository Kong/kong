-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

local _M = {}

_M.off = true

function _M:select_ids_by_key(key)
  local cred, _ = kong.db.keyauth_enc_credentials:select_by_key(key)
  return cred and { { id = cred.id } } or {}
end


return _M
