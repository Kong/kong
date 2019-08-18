local rbac  = require "kong.rbac"

local _M = {}

function _M:update(primary_key, entity, options)
  local row, err, err_t = self.super.update(self, primary_key, entity, options)

  -- cache invalidation
  if row then rbac.invalidate_rbac_user_cache(primary_key) end

  return row, err, err_t
end

return _M