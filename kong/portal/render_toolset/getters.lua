local singletons   = require "kong.singletons"
local ee           = require "kong.enterprise_edition"
local workspaces   = require "kong.workspaces"
local pl_string    = require "pl.stringx"


local function select_all_files()
  return singletons.db.files:select_all()
end


local function select_authenticated_developer()
  if singletons.render_ctx and singletons.render_ctx.developer then
    return singletons.render_ctx.developer
  end

  return nil
end


local function get_portal_name()
  local portal_config = singletons.render_ctx.portal

  return portal_config.name
end


local function select_portal_config()
  local portal_config = singletons.render_ctx.portal

  return portal_config.config
end


local function get_portal_redirect()
  local portal_config = singletons.render_ctx.portal

  return portal_config.redirect
end


local function select_kong_config()
  return ee.prepare_portal(singletons.render_ctx, singletons.configuration)
end


local function get_page_content()
  local content = singletons.render_ctx.content

  return content
end


local function select_theme_config()
  local theme_config = singletons.render_ctx.theme

  return theme_config
end


local function get_portal_urls()
  local conf = singletons.configuration
  local render_ctx = singletons.render_ctx
  local workspace = workspaces.get_workspace()
  local workspace_gsub = "^/" .. workspace.name .. "/"
  local portal_gui_url = workspaces.build_ws_portal_gui_url(conf, workspace)
  local portal_api_url = workspaces.build_ws_portal_api_url(conf, workspace)
  local current_path = string.gsub(render_ctx.route, workspace_gsub, "")
  local current_url = portal_gui_url .. current_path
  local current_breadcrumbs = pl_string.split(current_path, "/")

  return {
    current_breadcrumbs = current_breadcrumbs,
    current_path = current_path,
    current = current_url,
    api = portal_api_url,
    gui = portal_gui_url,
  }
end


return {
  select_all_files = select_all_files,
  select_authenticated_developer = select_authenticated_developer,
  select_portal_config = select_portal_config,
  select_kong_config   = select_kong_config,
  select_theme_config  = select_theme_config,
  get_portal_name      = get_portal_name,
  get_page_content     = get_page_content,
  get_portal_urls      = get_portal_urls,
  get_portal_redirect  = get_portal_redirect,
}
