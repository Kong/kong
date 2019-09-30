local singletons = require "kong.singletons"
local looper     = require "kong.portal.render_toolset.looper"

local function get_conf_attr_value(attr)
  local val
  if type(attr) ~= "table" then
    val = attr
  end

  if attr.value then
    val = attr.value
  end

  return val
end

local function map_conf_values(tbl)
  tbl = tbl or {}
  for key, value in pairs(tbl) do
    tbl[key] = get_conf_attr_value(tbl[key])
  end
  return tbl
end

local function get_map_value_fn(tbl)
  return function(key)
    return tbl[key]
  end
end

return function()
  local render_ctx = singletons.render_ctx
  local theme = {}
  looper.set_node(theme)

  local _theme = render_ctx.theme or {}
  for k, v in pairs(_theme) do
    theme[k] = v
  end

  theme.colors = map_conf_values(theme.colors)
  theme.color = get_map_value_fn(theme.colors)

  theme.fonts = map_conf_values(theme.fonts)
  theme.font = get_map_value_fn(theme.fonts)

  return theme
end
