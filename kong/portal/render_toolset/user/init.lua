local helpers       = require "kong.portal.render_toolset.helpers"
local singletons    = require "kong.singletons"

return function()
  local render_ctx = singletons.render_ctx
  local developer = helpers.tbl.deepcopy(render_ctx.developer or {})

  developer.is_authenticated = function()
    return render_ctx.developer ~= nil
  end

  developer.get = function(arg)
    return developer[arg]
  end

  return developer
end
