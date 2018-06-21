local api_helpers = require "kong.api.api_helpers"
local singletons  = require "kong.singletons"
local responses   = require "kong.tools.responses"
local endpoints   = require "kong.api.endpoints"
local reports     = require "kong.core.reports"
local utils       = require "kong.tools.utils"
local crud        = require "kong.api.crud_helpers"
local core_handler = require "kong.core.handler"
local uuid = require("kong.tools.utils").uuid
local workspaces = require "kong.workspaces"


local tostring    = tostring
local type        = type


return {
  ["/services"] = {
    POST = function(self, _, _, parent)
      api_helpers.resolve_url_params(self)
      return parent()
    end,
  },

  ["/services/:services"] = {
    PATCH  = function(self, _, _, parent)
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
    on_error = function(self)
      local err = self.errors[1]

      if type(err) ~= "table" then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(tostring(err))
      end

      if err.db then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err.message)
      end

      if err.unique then
        return responses.send_HTTP_CONFLICT(err.tbl)
      end

      if err.foreign then
        return responses.send_HTTP_NOT_FOUND(err.tbl)
      end

      return responses.send_HTTP_BAD_REQUEST(err.tbl or err.message)
    end,

    before = function(self, db, helpers)
      local id = self.params.services

      local parent_entity, _, err_t
      if not utils.is_valid_uuid(id) then
        parent_entity, _, err_t = db.services:select_by_name(id)

      else
        parent_entity, _, err_t = db.services:select({ id = id })
      end

      if err_t then
        return endpoints.handle_error(err_t)
      end

      if not parent_entity then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.services   = nil
      self.params.service_id = parent_entity.id
    end,

    GET = function(self)
      crud.paginated_set(self, singletons.dao.plugins)
    end,

    POST = function(self)
      crud.post(self.params, singletons.dao.plugins,
        function(data)
          local r_data = utils.deep_copy(data)
          r_data.config = nil
          r_data.e = "s"
          reports.send("api", r_data)
        end
      )
    end,

    PUT = function(self)
      crud.put(self.params, singletons.dao.plugins)
    end
  },
}
