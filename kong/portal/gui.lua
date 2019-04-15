local lapis = require "lapis"
local pl_file = require "pl.file"
local auth    = require "kong.portal.auth"
local responses   = {} -- XXX EE: remove this placeholder
local gui_helpers = require "kong.portal.gui_helpers"
local EtluaWidget = require("lapis.etlua").EtluaWidget


local kong = kong


local app = lapis.Application()


local function sitemap_handler(self)
  local config = kong.configuration

  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/sitemap.etlua"))
  gui_helpers.prepare_sitemap(self)
end


local function index_handler(self)
  local config = kong.configuration

  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/index.etlua"))
  gui_helpers.prepare_index(self)
end


app:enable("etlua")


app:before_filter(function(self)
  local config = kong.configuration
  local headers = ngx.req.get_headers()

  self.is_admin = headers["Kong-Request-Type"] == "editor"
  self.path = ngx.unescape_uri(self.req.parsed_url.path)

  if config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_subdomain(self)
  else
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil

  auth.authenticate_gui_session(self, kong.db, { responses = responses })
end)


app:match("/sitemap.xml", sitemap_handler)
app:match("/:workspace_name/sitemap.xml", sitemap_handler)


app:match("/:workspace_name(/*)", index_handler)
app:match("/", index_handler)


return app
