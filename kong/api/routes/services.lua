-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils       = require "kong.tools.utils"
local core_handler = require "kong.runloop.handler"
local route_collision = require "kong.enterprise_edition.workspaces.route_collision"
local portal_crud = require "kong.portal.crud_helpers"


local kong = kong


local function check_service(self, db, helpers)
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
end


return {
  ["/services/:services/routes"] = {
    POST = function(self, db, helpers, parent)
      check_service(self, db, helpers)

      local ok, err = route_collision.is_route_crud_allowed(self, core_handler.get_updated_router_immediate(), true)
      if not ok then
        return kong.response.exit(err.code, { message = err.message, collision = err.collision })
      end
      return parent()
    end
  },

  ["/services/:services/document_objects"] = {
    GET  = portal_crud.get_document_objects_by_service,
    POST = portal_crud.create_document_object_by_service,
  },

  ["/services/:services/routes/:routes"] = {
    PATCH = function(self, db, helpers, parent)
      check_service(self, db, helpers)

      local ok, err = route_collision.is_route_crud_allowed(self, core_handler.get_updated_router_immediate(), true)
      if not ok then
        return kong.response.exit(err.code, { message = err.message, collision = err.collision })
      end
      return parent()
    end,
  }
}
