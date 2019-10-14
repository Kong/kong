local lapis = require "lapis"
local ck = require "resty.cookie"
local pl_file = require "pl.file"
local pl_pretty   = require "pl.pretty"
local auth    = require "kong.portal.auth"
local workspaces  = require "kong.workspaces"
local gui_helpers = require "kong.portal.gui_helpers"
local crud_helpers = require "kong.portal.crud_helpers"
local EtluaWidget = require("lapis.etlua").EtluaWidget
local constants = require "kong.constants"
local ws_constants = constants.WORKSPACE_CONFIG
local renderer = require "kong.portal.renderer"

local kong = kong


local app = lapis.Application()


local function is_legacy()
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  return workspaces.retrieve_ws_config(ws_constants.PORTAL_IS_LEGACY, workspace)
end


local function sitemap_handler(self)
  local config = kong.configuration
  if (is_legacy()) then
    app:enable("etlua")
    app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/sitemap.etlua"))
    gui_helpers.prepare_sitemap(self)
  end
end


local function asset_handler(self)
  renderer.set_render_ctx(self)
  local asset = renderer.compile_asset()

  if asset then
    return kong.response.exit(200, asset)
  end
end


local function index_handler(self)
  if (is_legacy()) then
    app:enable("etlua")
    local config = kong.configuration
    app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/index.etlua"))
    gui_helpers.prepare_index(self)
    return
  end

  if self.path:sub(1, #"/assets") == "/assets" then
    asset_handler(self)
  end

  renderer.set_render_ctx(self)
  local view = renderer.compile_layout()

  return kong.response.exit(200, view)
end

app.handle_404 = function(self)
  return kong.response.exit(404, constants.PORTAL_RENDERER.FALLBACK_404)
end

app.handle_error = function(self, err, trace)
  if err then
    if type(err) ~= "string" then
      err = pl_pretty.write(err)
    end
    if string.find(err, "don't know how to respond to", nil, true) then
      return kong.response.exit(405, { message = "Method not allowed"})
    end
  end

  ngx.log(ngx.ERR, err, "\n", trace)
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end

app:before_filter(function(self)
  local config = kong.configuration
  local headers = ngx.req.get_headers()

  local cookie, err = ck:new()
  if not cookie then
    ngx.log(ngx.ERR, err)
    return
  end

  local redirect = cookie:get("redirect")
  if redirect then
    local ok, err = cookie:set({
      key = "redirect",
      value = "",
      path = "/",
      max_age = 0,
    })

    if not ok then
       ngx.log(ngx.ERR, err)
       return
    end

    if config.portal_gui_use_subdomains then
      return ngx.redirect('/' .. redirect)
    end

    local workspace_name = self.params.workspace_name or workspaces.DEFAULT_WORKSPACE
    return ngx.redirect('/' .. workspace_name .. '/' .. redirect)
  end

  self.is_admin = headers["Kong-Request-Type"] == "editor"
  self.path = ngx.unescape_uri(self.req.parsed_url.path)

  if self.is_admin then
    self.path = string.gsub(self.path, "/", "", 1)
  end

  if config.portal_gui_use_subdomains and not self.is_admin then
    gui_helpers.set_workspace_by_subdomain(self)
  else
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil
  crud_helpers.exit_if_portal_disabled()
  auth.authenticate_gui_session(self, kong.db, {})
end)

app:match("/sitemap.xml", sitemap_handler)
app:match("/:workspace_name/sitemap.xml", sitemap_handler)

app:match("/:workspace_name(/*)", index_handler)
app:match("/", index_handler)


return app
