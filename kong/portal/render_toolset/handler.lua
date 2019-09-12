local portal = require("kong.portal.render_toolset.portal")
local page   = require("kong.portal.render_toolset.page")
local user   = require("kong.portal.render_toolset.user")
local theme  = require("kong.portal.render_toolset.theme")
local helpers  = require("kong.portal.render_toolset.helpers")

return function(template)
  local ctx = {
    portal = portal(),
    theme = theme(),
    user = user(),
    page = page(),
    helpers = helpers
  }

  -- Locale helper, internationalization support v1
  ctx.l = function(arg, fallback)
    return template.compile(ctx.page.l(arg, fallback))(ctx)
  end

  -- Expose commonly used helpers to root context
  ctx.each = ctx.helpers.each
  ctx.print = ctx.helpers.print

  return ctx
end
