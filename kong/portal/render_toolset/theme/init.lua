local helpers       = require "kong.portal.render_toolset.helpers"
local singletons    = require "kong.singletons"

local function get_val(attr)
  local val
  if type(attr) ~= "table" then
    val = attr
  end

  if attr.value then
    val = attr.value
  end

  return val
end

return function()
  local render_ctx = singletons.render_ctx
  local theme = helpers.tbl.deepcopy(render_ctx.theme or {})

  theme.colors = theme.colors or {}
  for k, color in pairs(theme.colors) do
    theme.colors[k] = get_val(color)
  end

  theme.fonts = theme.fonts or {}
  for k, font in pairs(theme.fonts or {}) do
    theme.fonts[k] = get_val(font)
  end

  theme.color = function(key)
    return theme.colors[key]
  end

  theme.font = function (key)
    return theme.fonts[key]
  end
  
  return theme
end
