local singletons  = require "kong.singletons"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid
local workspaces = require "kong.workspaces"


local kong = kong


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "s"
  reports.send("api", r_data)
  return data
end


return {
  ["/services/:services/routes"] = {
    before = function(self, db, helpers)
      local old_wss = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      core_handler.build_router(db, uuid())
      ngx.ctx.workspaces = old_wss

      -- check for the service existence
      local id = self.params.services
      local entity, _, err_t
      if not utils.is_valid_uuid(id) then
        entity, _, err_t = db.services:select_by_name(id)
      else
        entity, _, err_t = db.services:select({ id = id })
      end

      if not entity or err_t then
        return kong.response.exit(404, {message = "Not found" })
      end
    end,

    POST = function(self, _, _, parent)
      if workspaces.is_route_colliding(self, singletons.router) then
        local err = "API route collides with an existing API"
        return kong.response.exit(409, { message = err })
      end
      return parent()
    end
  },

  ["/services/:services/plugins"] = {
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },
}
