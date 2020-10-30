-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
  ctx.tbl      = ctx.helpers.tbl
  ctx.str      = ctx.helpers.str
  ctx.each     = ctx.tbl.each
  ctx.print    = ctx.helpers.print
  ctx.json_decode = helpers.json_decode
  ctx.json_encode = helpers.json_encode
  ctx.markdown    = ctx.helpers.markdown

  return ctx
end
