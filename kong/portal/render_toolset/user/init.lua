local singletons    = require "kong.singletons"

return function()
  local user = {}

  user.is_authenticated = function()
    local render_ctx = singletons.render_ctx
    return render_ctx.developer ~= nil and next(render_ctx.developer) ~= nil
  end

  user.get = function(arg)
    local render_ctx = singletons.render_ctx
    return render_ctx.developer[arg]
  end

  return user
end
