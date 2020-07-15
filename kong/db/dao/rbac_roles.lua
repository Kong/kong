local utils = require("kong.tools.utils")


local rbac_roles = {}


function rbac_roles:cache_key(id, arg2, arg3, arg4, arg5, ws_id)
  if type(id) == "table" then
    id = id.id
  end

  if utils.is_valid_uuid(id) then
    -- Always return the cache_key without a workspace
    return "rbac_roles:" .. id .. ":::::"
  end

  return self.super.cache_key(self, id, arg2, arg3, arg4, arg5, ws_id)
end


return rbac_roles
