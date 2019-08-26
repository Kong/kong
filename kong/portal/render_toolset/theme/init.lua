local helpers       = require "kong.portal.render_toolset.helpers"
local singletons    = require "kong.singletons"

return function()
  local render_ctx = singletons.render_ctx
  local theme = helpers.tbl.deepcopy(render_ctx.theme or {})

  theme.color = function(key)
    return theme.colors[key]
  end
  
  theme.font = function (key)
    return theme.fonts[key]
  end
  
  return theme
end