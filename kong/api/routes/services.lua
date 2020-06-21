local singletons  = require "kong.singletons"
local utils       = require "kong.tools.utils"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid
local route_collision = require "kong.enterprise_edition.workspaces.route_collision"
local portal_crud = require "kong.portal.crud_helpers"


local kong = kong


return {
  ["/services/:services/routes"] = {
    before = function(self, db, helpers)
      if kong.configuration.route_validation_strategy == 'smart'  then
        -- XXXCORE is this flipping still necessary?
        local old_ws = ngx.ctx.workspace
        ngx.ctx.workspace = nil
        core_handler.build_router(db, uuid())
        ngx.ctx.workspace = old_ws
      end

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
      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router, true)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end
      return parent()
    end
  },

  ["/services/:services/document_objects"] = {
    GET  = portal_crud.get_document_objects_by_service,
    POST = portal_crud.create_document_object_by_service,
  },

  ["/services/:services/routes/:routes"] = {
    PATCH = function(self, _, _, parent)
      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router, true)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end
      return parent()
    end,
  }
}
