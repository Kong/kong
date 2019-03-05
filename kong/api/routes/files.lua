local constants     = require "kong.constants"
local ws_helper     = require "kong.workspaces.helper"

local ws_constants = constants.WORKSPACE_CONFIG

local function check_portal_status(helpers)
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1] or {}
  local portal = ws_helper.retrieve_ws_config(ws_constants.PORTAL, workspace)
  if not portal then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end


return {
  ["/files"] = {
    before = function(self, db, helpers)
      check_portal_status(helpers)
    end,

    -- List all files stored in the portal file system
    GET = function(self, db, _, parent)
      if not self.args.uri.size then
        self.args.uri.size = 100
      end

      return parent()
    end,
  },
}
