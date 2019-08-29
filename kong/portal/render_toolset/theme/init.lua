local helpers       = require "kong.portal.render_toolset.helpers"
local singletons    = require "kong.singletons"

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
  local theme = helpers.tbl.deepcopy(render_ctx.theme or {})

  theme.colors = map_conf_values(theme.colors)
  theme.color = get_map_value_fn(theme.colors)

  theme.fonts = map_conf_values(theme.fonts)
  theme.font = get_map_value_fn(theme.fonts)

  return theme
end
