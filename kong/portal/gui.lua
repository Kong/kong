local lapis       = require "lapis"
local singletons  = require "kong.singletons"
local ee          = require "kong.enterprise_edition"
local pl_file     = require "pl.file"
local workspaces  = require "kong.workspaces"
local EtluaWidget = require("lapis.etlua").EtluaWidget
local responses   = require "kong.tools.responses"


local app = lapis.Application()

app:enable("etlua")
app.layout = EtluaWidget:load(pl_file.read("kong/portal/views/index.etlua"))


app:match("/:workspace(/*)", function(self)
  local workspace = workspaces.get_req_workspace(self.params.workspace)

  if not workspace[1] then
    workspace = workspaces.get_req_workspace(workspaces.DEFAULT_WORKSPACE)
  end

  if not workspace[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  self.params.workspace = workspace[1]

  self.configs = ee.prepare_portal(singletons.configuration, self)
end)


app:match("/", function(self)
  local workspace = workspaces.get_req_workspace(workspaces.DEFAULT_WORKSPACE)

  if not workspace[1] then
    responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  self.params.workspace = workspace[1]

  self.configs = ee.prepare_portal(singletons.configuration, self)
end)


return app
