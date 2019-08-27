local helpers       = require "kong.portal.render_toolset.helpers"
local workspaces    = require "kong.workspaces"
local singletons    = require "kong.singletons"

return function()
  local conf = singletons.configuration
  local render_ctx = singletons.render_ctx
  local workspace = workspaces.get_workspace()
  local workspace_path_gsub = "^/" .. workspace.name .. "/"
  local portal_gui_url = workspaces.build_ws_portal_gui_url(conf, workspace)
  local page = helpers.tbl.deepcopy(render_ctx.content or {})

  -- Table containing only page content
  -- Used for spec rendering
  page.contents = render_ctx.content

  -- Helper variables
  page.path = string.gsub(render_ctx.route, workspace_path_gsub, "")
  page.url = portal_gui_url .. "/" .. page.path

  -- Locale function
  page.l = function(property, fallback)
    return (page.locale and page.locale[property]) or fallback
  end

  -- Build breadcrumbs object with helpful properties
  page.breadcrumbs = {}
  local crumbs = helpers.str.split(page.path, "/")
  for i,v in ipairs(crumbs) do
    local path_parts = {unpack(crumbs, 1, i)}
    local v_unslug = v.gsub(v, "-"," ")
    table.insert(page.breadcrumbs, {
      name = v,
      display_name = v_unslug.gsub(" "..v_unslug, "%W%l", string.upper):sub(2),
      path = table.concat(path_parts, "/"),
      is_last = i == #crumbs,
      is_first = i == 1,
    })
  end

  return page
end

