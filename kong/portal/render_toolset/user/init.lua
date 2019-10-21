local singletons    = require "kong.singletons"
local rbac          = require "kong.rbac"
local constants     = require "kong.constants"
local looper = require "kong.portal.render_toolset.looper"

local PORTAL_PREFIX = constants.PORTAL_PREFIX


return function()
  local user = {}
  looper.set_node(user)

  user.is_authenticated = function()
    local render_ctx = singletons.render_ctx
    return render_ctx.developer ~= nil and next(render_ctx.developer) ~= nil
  end

  user.has_role = function(role)
    local render_ctx = singletons.render_ctx
    local developer = render_ctx.developer
    if not developer then
      return false
    end

    local rbac_user = developer.rbac_user
    if not rbac_user then
      return false
    end

    local rbac_roles, err = rbac.get_user_roles(singletons.db, rbac_user)
    if err then
      return false
    end

    for _, v in ipairs(rbac_roles) do
      if v.name == PORTAL_PREFIX .. role then
        return true
      end
    end

    return false
  end

  user.get = function(arg)
    local render_ctx = singletons.render_ctx
    return render_ctx.developer[arg]
  end

  return user
end
