local lapis = require "lapis"
local pl_file = require "pl.file"
local auth    = require "kong.portal.auth"
local singletons  = require "kong.singletons"
local responses   = require "kong.tools.responses"
local gui_helpers = require "kong.portal.gui_helpers"
local EtluaWidget = require("lapis.etlua").EtluaWidget


local app = lapis.Application()
local config = singletons.configuration


app:enable("etlua")


app:before_filter(function(self)
  self.path = ngx.unescape_uri(self.req.parsed_url.path)

  if config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_subdomain(self)
  end
end)


app:match("/sitemap.xml", function(self)
  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/sitemap.etlua"))

  if not config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil

  auth.authenticate_gui_session(self, singletons.dao, { responses = responses })
  gui_helpers.prepare_sitemap(self)
end)


app:match("/:workspace_name/sitemap.xml", function(self)
  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/sitemap.etlua"))

  if not config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil

  auth.authenticate_gui_session(self, singletons.dao, { responses = responses })
  gui_helpers.prepare_sitemap(self)
end)


app:match("/:workspace_name(/*)", function(self)
  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/index.etlua"))

  if not config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil

  auth.authenticate_gui_session(self, singletons.dao, { responses = responses })
  gui_helpers.prepare_index(self)
end)


app:match("/", function(self)
  app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/index.etlua"))

  if not config.portal_gui_use_subdomains then
    gui_helpers.set_workspace_by_path(self)
  end

  ngx.ctx.workspaces = self.workspaces
  self.workspaces = nil

  auth.authenticate_gui_session(self, singletons.dao, { responses = responses })
  gui_helpers.prepare_index(self)
end)


return app
