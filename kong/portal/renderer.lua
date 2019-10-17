local singletons  = require "kong.singletons"
local pl_stringx   = require "pl.stringx"
local workspaces   = require "kong.workspaces"
local permissions  = require "kong.portal.permissions"
local file_helpers = require "kong.portal.file_helpers"
local template     = require "resty.template"
local lyaml        = require "lyaml"
local handler      = require "kong.portal.render_toolset.handler"
local constants    = require "kong.constants"

local LAYOUTS = constants.PORTAL_RENDERER.LAYOUTS
local FALLBACK_404 = constants.PORTAL_RENDERER.FALLBACK_404
local SITEMAP = constants.PORTAL_RENDERER.SITEMAP

local ws_constants  = constants.WORKSPACE_CONFIG
local yaml_load = lyaml.load

local portal_conf_values = {
  "auth",
  "auth_conf",
  "session_conf",
  "auto_approve",
  "token_exp",
  "invite_email",
  "access_request_email",
  "approved_email",
  "reset_email",
  "reset_success_email",
  "emails_from",
  "emails_reply_to",
}


template.caching(false)
template.load = function(path)
  -- look into alternative ways of passing info
  local ctx = singletons.render_ctx or {}
  local theme = ctx.theme or { name = "" }

  if type(path) == 'table' and path.contents then
    return path.contents
  end

  local template = singletons.db.files:select_file_by_theme(path, theme.name)
  if not template then
    return path
  end

  return template.contents
end


local function build_url_obj(route, page, url_map)
  local workspace = workspaces.get_workspace()

  local headmatter = page.headmatter or {}
  if headmatter.private then
    return
  end

  local url_items = {}
  local page_url = workspaces.build_ws_portal_gui_url(kong.configuration, workspace) .. route
  page_url = pl_stringx.rstrip(page_url, '/')
  url_items["loc"] = page_url

  local updated_at = page.updated_at or page.created_at
  local formated_date = os.date("%Y-%d-%m", updated_at / 1000)
  url_items["lastmod"] = formated_date
  url_map[page_url] = url_items
end


local function build_sitemap_obj()
  local router_info = singletons.portal_router.introspect()
  local ws_name = workspaces.get_workspace().name
  local router = router_info.router[ws_name] or {}
  local routes = {}

  for k, v in pairs(router.collection or {}) do
    routes[k] = v
  end

  for k, v in pairs(router.content or {}) do
    routes[k] = v
  end

  for k, v in pairs(router.explicit or {}) do
    routes[k] = v
  end

  local url_map = {}
  local url_list = {}

  for route, page in pairs(routes) do
    build_url_obj(route, page, url_map)
  end

  for key, url_item in pairs(url_map) do
    table.insert(url_list, url_item)
  end

  return url_list
end


local function set_path(path)
  path = pl_stringx.rstrip(path, '/')
  path = pl_stringx.lstrip(path, '/')

  if path == '' or path == '/' then
    path = 'index'
  end

  return path
end


local function set_route_config(path)

  path = pl_stringx.rstrip(path, '/')
  path = pl_stringx.lstrip(path, '/')

  if path[1] ~= "/" then
    path = "/" .. path
  end

  return singletons.portal_router.get(path)
end


local function set_asset(ctx)
  local path = ctx.path
  local theme = ctx.theme

  return singletons.db.files:select_file_by_theme(path, theme.name)
end


local function get_missing_layout(ctx)
  local theme = ctx.theme
  return singletons.db.files:select_file_by_theme("layouts/system/404.html",
                                                  theme.name)
end


local function set_layout(ctx)
  local theme = ctx.theme
  local path = ctx.layout

  -- Missing
  if not path then
    return get_missing_layout(ctx)
  end

  -- Attempt to load layout with extension
  local layout = singletons.db.files:select_file_by_theme('layouts/' .. path .. '.html',
                                                          theme.name)

  -- Attempt loading a layout without extension
  if not layout then
    layout = singletons.db.files:select_file_by_theme('layouts/' .. path,
                                                      theme.name)
  end

  -- Could not find layout by path return 404
  if not layout then
    layout = get_missing_layout(ctx)
  end

  return layout
end


local function set_layout_by_permission(route_config, developer, workspace, config, path)
  if not next(route_config) then
    return LAYOUTS.UNSET
  end

  local router = singletons.portal_router
  local db = singletons.db

  local redirect = config.redirect
  local unauthenticated_r = redirect and redirect.unauthenticated
  if not unauthenticated_r then
    unauthenticated_r = LAYOUTS.LOGIN
  end

  local unauthorized_r = redirect and redirect.unauthorized
  if not unauthorized_r then
    unauthorized_r = LAYOUTS.UNAUTHORIZED
  end

  local file
  local headmatter = route_config.headmatter or {}
  local workspace = workspaces.get_workspace()
  local portal_auth = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH,
                                                    workspace)

  local no_auth = portal_auth == nil or portal_auth == ''
  if headmatter.private and no_auth then
    return LAYOUTS.UNSET
  end

  local readable_by = headmatter.readable_by
  local has_permissions = type(readable_by) == "table" and #readable_by > 0
  local auth_required = has_permissions or readable_by == "*"

  -- route requires auth, no developer preset, redirect
  if not next(developer) and auth_required then
    file = router.find_highest_priority_file_by_route(db,
                                                      "/" .. unauthenticated_r)
    -- fallback in the case that unauthenticated content not found
    if not file then
      return LAYOUTS.LOGIN
    end
  end

  -- route has permissions, developer preset, check permissions
  if not file and has_permissions then
    local ok = permissions.can_read(developer, workspace.name,
                                         route_config.path)

    -- permissions check failed, redirect
    if not ok then
      file = router.find_highest_priority_file_by_route(db,
                                                        "/" .. unauthorized_r)
      -- fallback in the case that unauthorized content not found
      if not file then
        return LAYOUTS.UNAUTHORIZED
      end
    end
  end

  if not file then
    return route_config.layout
  end

  local parsed_file = file_helpers.parse_content(file)
  if not parsed_file then
    return LAYOUTS.UNSET
  end

  return parsed_file.layout
end


local function set_portal_config()
  local file = singletons.db.files:select_portal_config()
  if not file then
    return { theme = "default" }
  end

  local contents = yaml_load(file.contents)
  if not contents then
    return { theme = "default" }
  end

  if not contents["theme"] then
    contents["theme"] = "default"
  end

  if not contents["config"] then
    contents["config"] = {}
  end

  for _, v in ipairs(portal_conf_values) do
    if not contents["config"][v] then
      local ws = workspaces.get_workspace()
      contents["config"][v] = workspaces.retrieve_ws_config("portal_" .. v, ws)
    end
  end

  return contents
end


local function set_theme_config(portal_theme_conf)
  local theme_name = portal_theme_conf
  if type(portal_theme_conf) == "table" then
    theme_name = portal_theme_conf.name
  end

  local file = singletons.db.files:select_theme_config(theme_name)
  if not file then
    return {
      name = theme_name
    }
  end

  local contents = yaml_load(file.contents)
  if not contents then
    return {
      name = theme_name
    }
  end

  contents.name = theme_name

  if type(portal_theme_conf) == "table" then
    if portal_theme_conf.colors then
      contents.colors = contents.colors or {}
      for k, v in pairs(portal_theme_conf.colors) do
        contents.colors[k] = v
      end
    end

    if portal_theme_conf.fonts then
      contents.fonts = contents.fonts or {}
      for k, v in pairs(portal_theme_conf.fonts) do
        contents.fonts[k] = v
      end
    end
  end

  return contents
end


local function set_render_ctx(self)
  -- 1. Set Portal Config
  -- 2. Set Theme Config
  -- 3. Retrieve Initial Route Config
  -- 4. Get Developer
  -- 4. Get layout by permission
  -- 5. Lookup layout

  local workspace = workspaces.get_workspace()
  local portal_config = set_portal_config()
  if not portal_config then
    return false, "could not retrieve portal config"
  end

  if not portal_config.theme then
    portal_config.theme = "default"
  end

  local theme_config = set_theme_config(portal_config.theme)
  if not theme_config then
    return false, "could not retrieve theme config"
  end

  local route_config
  if self.is_admin then
    local file = singletons.db.files:select_by_path(self.path)
    if not self.path then
      file = {}
    end

    route_config = file_helpers.parse_content(file)
  end

  if not route_config then
    route_config = set_route_config(self.path)
  end

  if not route_config then
    route_config = {}
  end

  local developer = self.developer or {}
  local path   = set_path(self.path)
  local layout = set_layout_by_permission(route_config, developer, workspace, portal_config)

  singletons.render_ctx = {
    route_config  = route_config,
    portal        = portal_config,
    theme         = theme_config,
    developer     = developer,
    layout        = layout,
    path          = path,
  }
end


local function compile_layout()
  local ctx = singletons.render_ctx
  local layout = set_layout(ctx)
  if not layout then
    return FALLBACK_404
  end

  return template.compile(layout)(handler(template))
end


local function compile_asset()
  local ctx = singletons.render_ctx
  local asset = set_asset(ctx)
  if not asset then
    return
  end

  if string.find(asset.path, 'css', 1, true) then
    return template.compile(asset)(handler(template))
  end

  return asset.contents
end


local function compile_sitemap()
  local xml_urlset = build_sitemap_obj()

  return template.compile(SITEMAP)({ xml_urlset = xml_urlset })
end


return {
  compile_layout = compile_layout,
  compile_sitemap = compile_sitemap,
  compile_asset  = compile_asset,
  set_render_ctx = set_render_ctx,
}
