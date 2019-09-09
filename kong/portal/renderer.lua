local singletons  = require "kong.singletons"
local pl_stringx   = require "pl.stringx"
local workspaces   = require "kong.workspaces"
local permissions  = require "kong.portal.permissions"
local template     = require "resty.template"
local lyaml        = require "lyaml"
local handler      = require "kong.portal.render_toolset.handler"


local yaml_load   = lyaml.load

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

local FALLBACK_404 = '<html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The page you are requesting cannot be found.</p></body></html>'


template.caching(false)
template.load = function(path)
  -- look into alternative ways of passing info
  local ctx = singletons.render_ctx
  local theme = ctx.theme.name

  if type(path) == 'table' and path.contents then
    return path.contents
  end

  local template = singletons.db.files:select_file_by_theme(path, theme)
  if not template then
    return path
  end

  return template.contents
end


local function set_path(path)
  local workspace = workspaces.get_workspace()

  path = pl_stringx.replace(path, '/' .. workspace.name .. '/', '')
  path = pl_stringx.replace(path, '/' .. workspace.name, '')
  path = pl_stringx.rstrip(path, '/')
  path = pl_stringx.lstrip(path, '/')

  if path == '' or path == '/' then
    path = 'index'
  end

  return path
end


local function set_route_config(path)
  local workspace = workspaces.get_workspace()
  path = pl_stringx.replace(path, '/' .. workspace.name .. '/', '')
  path = pl_stringx.replace(path, '/' .. workspace.name, '')
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
  local content = ctx.content

  content.title = "Page Not Found"

  return singletons.db.files:select_file_by_theme("layouts/404.html",
                                                  theme.name)
end


local function set_layout(ctx)
  local theme   = ctx.theme
  local content = ctx.content
  local path = content.layout

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


local function set_content(route_config, developer, workspace, config)
  if not next(route_config) then
    return {}
  end

  local router = singletons.portal_router
  local db = singletons.db

  local redirect = config.redirect
  local unauthenticated_r = redirect and redirect.unauthenticated
  if not unauthenticated_r then
    unauthenticated_r = "login"
  end

  local unauthorized_r = redirect and redirect.unauthorized
  if not unauthorized_r then
    unauthorized_r = "unauthorized"
  end

  local readable_by = route_config.readable_by
  local has_permissions = type(readable_by) == "table" and #readable_by > 0
  local auth_required = has_permissions or readable_by == "*"

  -- route requires auth, no developer preset, redirect
  local file
  if not developer and auth_required then
    file = router.find_highest_priority_file_by_route(db,
                                                      "/" .. unauthenticated_r)
    -- fallback in the case that unauthenticated content not found
    if not file then
      return { layout = "login" }
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
        return { layout = "unauthorized" }
      end
    end
  end

  -- auth checks have passed, fetch the file
  if not file then
    file = singletons.db.files:select_by_path(route_config.path)
  end

  if not file then
    return {}
  end

  local parsed_content = yaml_load(file.contents)
  if not parsed_content then
    return {}
  end

  return parsed_content
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
  local workspace     = workspaces.get_workspace()
  local route         = self.path
  local developer     = self.developer
  local path          = set_path(route)
  local route_config  = set_route_config(route)
  local portal_config = set_portal_config()
  local theme_config  = set_theme_config(portal_config.theme)
  local content       = set_content(route_config, developer, workspace, portal_config)

  singletons.render_ctx = {
    path      = path,
    route     = route,
    content   = content,
    theme     = theme_config,
    portal    = portal_config,
    developer = developer,
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


return {
  compile_layout = compile_layout,
  compile_asset  = compile_asset,
  set_render_ctx = set_render_ctx,
}
