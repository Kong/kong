local helpers       = require "kong.portal.render_toolset.helpers"
local workspaces    = require "kong.workspaces"
local singletons    = require "kong.singletons"
local markdown      = require "markdown"
local lyaml         = require "lyaml"

local yaml_load     = lyaml.load


local function markdownify(contents, route_config)
  local path_meta = route_config.path_meta or {}
  local extension = path_meta.extension or ""
  if extension == "md" or extension == "markdown" then
    return markdown(contents)
  end

  return contents
end


return function()
  local conf = singletons.configuration
  local render_ctx = singletons.render_ctx
  local workspace = workspaces.get_workspace()
  local workspace_path_gsub = "^/" .. workspace.name .. "/"
  local portal_gui_url = workspaces.build_ws_portal_gui_url(conf, workspace)
  local route_config = render_ctx.route_config or {}
  local page = helpers.tbl.deepcopy(route_config.headmatter or {})

  -- Table containing only page content
  -- Used for spec rendering
  local render_ctx = render_ctx or {}
  local route_config = render_ctx.route_config or {}
  page.body = markdownify(route_config.body or "", route_config)
  page.parsed_body = yaml_load(page.body) or {}

  -- Helper variables
  local route_config = render_ctx.route_config or {}
  local route = route_config.route or render_ctx.path
  route = string.gsub(route, workspace_path_gsub, "")
  if helpers.str.startswith(route, "/") then
    route = string.gsub(route, "/", "", 1)
  end

  page.route = route
  page.url = portal_gui_url .. "/" .. page.route

  -- Locale function
  page.l = function(property, fallback)
    return (page.locale and page.locale[property]) or fallback
  end

  -- Build breadcrumbs object with helpful properties
  page.breadcrumbs = {}
  local crumbs = helpers.str.split(page.route, "/")
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
