-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces      = require "kong.workspaces"
local utils           = require "kong.tools.utils"

local fmt = string.format
local kong = kong
local unescape_uri = ngx.unescape_uri

local _M = {}


function _M.before_filter(self)
  local req_id = utils.random_string()

  ngx.ctx.admin_api = {
    req_id = req_id,
  }
  ngx.header["X-Kong-Status-Request-ID"] = req_id

  do
    -- in case of endpoint with missing `/`, this block is executed twice.
    -- So previous workspace should be dropped
    ngx.ctx.rbac = nil
    workspaces.set_workspace(nil)

    -- workspace name: if no workspace name was provided as the first segment
    -- in the path (:8001/:workspace/), consider it is the default workspace
    local ws_name = workspaces.DEFAULT_WORKSPACE
    if self.params.workspace_name then
      ws_name = unescape_uri(self.params.workspace_name)
    end

    -- fetch the workspace for current request
    local workspace, err = kong.db.workspaces:select_by_name(ws_name)
    if err then
      ngx.log(ngx.ERR, err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end
    if not workspace then
      kong.response.exit(404, {message = fmt("Workspace '%s' not found", ws_name)})
    end

    -- set fetched workspace reference into the context
    workspaces.set_workspace(workspace)
    self.params.workspace_name = nil
  end
end


return _M
