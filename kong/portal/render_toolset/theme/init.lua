local Theme = {}
local getters = require "kong.portal.render_toolset.getters"

function Theme:setup()
  local ctx = getters.select_theme_config()

  return self
          :set_ctx(ctx)
          :next()
end

function Theme:colors(arg)
  local ctx = self.ctx.colors
  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next()
end


function Theme:fonts(arg)
  local ctx = self.ctx.fonts

  return self
          :set_ctx(ctx)
          :next()
          :val(arg)
          :next()
end


return Theme
