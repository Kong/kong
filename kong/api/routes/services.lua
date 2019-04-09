local api_helpers = require "kong.api.api_helpers"
local singletons  = require "kong.singletons"
local responses   = require "kong.tools.responses"
local reports     = require "kong.reports"
local utils       = require "kong.tools.utils"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid
local workspaces = require "kong.workspaces"


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "s"
  reports.send("api", r_data)
  return data
end


return {
  ["/services"] = {
    POST = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/services/:services"] = {
    PUT = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
    PATCH = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

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
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    POST = function(self, _, _, parent)
      if workspaces.is_route_colliding(self, singletons.router) then
        local err = "API route collides with an existing API"
        return responses.send_HTTP_CONFLICT(err)
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
