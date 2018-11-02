local lapis       = require "lapis"
local singletons  = require "kong.singletons"
local ee          = require "kong.enterprise_edition"
local workspaces  = require "kong.workspaces"
local responses   = require "kong.tools.responses"
local pl_file     = require "pl.file"
local pl_stringx = require "pl.stringx"
local EtluaWidget = require("lapis.etlua").EtluaWidget

local config = singletons.configuration
local app = lapis.Application()

app:enable("etlua")
app.layout = EtluaWidget:load(pl_file.read(config.prefix .. "/portal/views/index.etlua"))

app:before_filter(function(self)
  if not config.portal_gui_use_subdomains then
    return
  end

  local host = self.req.parsed_url.host
  if host == config.portal_gui_host then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local split_host = pl_stringx.split(self.req.parsed_url.host, '.')
  if not split_host[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local parsed_host = split_host[1]
  self.workspaces = workspaces.get_req_workspace(parsed_host)
  if not self.workspaces[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end
end)

app:match("/:workspace_name(/*)", function(self)
  self.workspaces = self.workspaces or {}

  if not self.workspaces[1] and not config.portal_gui_use_subdomains then
    self.workspaces = workspaces.get_req_workspace(self.params.workspace_name)
  end

  if not self.workspaces[1] and not config.portal_gui_use_subdomains then
    self.workspaces = workspaces.get_req_workspace(workspaces.DEFAULT_WORKSPACE)
  end

  if not self.workspaces[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  self.workspace = self.workspaces[1]
  self.workspaces = nil
  self.configs = ee.prepare_portal(config, self)
end)


app:match("/", function(self)
  self.workspaces = self.workspaces or {}

  if not self.workspaces[1] and not config.portal_gui_use_subdomains then
    self.workspaces = workspaces.get_req_workspace(workspaces.DEFAULT_WORKSPACE)
  end

  if not self.workspaces[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  self.workspace = self.workspaces[1]
  self.workspaces = nil
  self.configs = ee.prepare_portal(config, self)
end)


return app
