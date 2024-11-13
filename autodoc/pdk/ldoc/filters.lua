local output_folder = "pdk"
local pl_template = require "pl.template"

return {
  nav = function(t)
    local tf = assert(io.open("autodoc/pdk/ldoc/nav_yml.ltp", "rb"))
    local template = tf:read("*all")
    tf:close()

    local new_nav_yml = assert(pl_template.substitute(template, {
      modules  = t,
      base_url = "/" .. output_folder,
      _parent = _G,
    }))
    print(new_nav_yml)
  end,

  json = function(t)
    local tf = assert(io.open("autodoc/pdk/ldoc/json.ltp", "rb"))
    local template = tf:read("*all")
    tf:close()

    local json_str = assert(pl_template.substitute(template, {
      modules  = t,
      base_url = "/" .. output_folder,
      _parent = _G,
    }))
    print(json_str)
  end,
}
