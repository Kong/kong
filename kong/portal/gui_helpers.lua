local cjson   = require "cjson"
local pl_stringx  = require "pl.stringx"
local workspaces  = require "kong.workspaces"
local singletons  = require "kong.singletons"
local renderer    = require "kong.portal.renderer"
local responses   = require "kong.tools.responses"
local ee          = require "kong.enterprise_edition"


local _M = {}
local config = singletons.configuration


local function send_workspace_not_found_error(err)
  local err_msg = 'failed to retrieve workspace for the request (reason: ' .. err .. ')'
  responses.send_HTTP_INTERNAL_SERVER_ERROR(err_msg)
end


function _M.prepare_index(self)
  local page, partials, spec = renderer.compile_assets(self)
  self.page = cjson.encode(page)
  self.spec = cjson.encode(spec)
  self.partials = cjson.encode(partials)
  self.configs = ee.prepare_portal(self, config)
end


function _M.prepare_sitemap(self)
  local pages = renderer.compile_sitemap(self)
  self.xml_urlset = pages
end


function _M.set_workspace_by_subdomain(self)
  self.workspaces = {}

  local host = self.req.parsed_url.host
  if host == config.portal_gui_host then
    send_workspace_not_found_error('no subdomain set in url')
  end

  local split_host = pl_stringx.split(self.req.parsed_url.host, '.')
  if not split_host[2] then
    send_workspace_not_found_error('no subdomain set in url')
  end

  local parsed_host = split_host[1]
  self.workspaces = workspaces.get_req_workspace(parsed_host)
  if not self.workspaces[1] then
    send_workspace_not_found_error('workspace "' .. parsed_host .. '" could not be found')
  end
end


function _M.set_workspace_by_path(self)
  self.workspaces = {}

  if self.params.workspace_name then
    self.workspaces = workspaces.get_req_workspace(self.params.workspace_name)
  end

  if not self.workspaces[1] then
    self.workspaces = workspaces.get_req_workspace(workspaces.DEFAULT_WORKSPACE)
  end

  if not self.workspaces[1] then
    send_workspace_not_found_error(
      'workspace "' .. workspaces.DEFAULT_WORKSPACE .. '" could not be found'
    )
  end
end


return _M
