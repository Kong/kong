-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local route_collision = require "kong.enterprise_edition.workspaces.route_collision"
local singletons = require "kong.singletons"
local core_handler = require "kong.runloop.handler"
local uuid = require("kong.tools.utils").uuid


local kong = kong


local function rebuild_routes(db)
  if kong.configuration.route_validation_strategy == 'smart'  then
    core_handler.build_router(db, uuid())
  end
end


return {
  ["/routes"] = {
    POST = function(self, db, helpers, parent)
      rebuild_routes(db)

      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router, true)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end

      return parent()
    end,
    GET = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end
  },

  ["/routes/:routes"] = {
    GET = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,
    PUT = function(self, db, helpers, parent)
      rebuild_routes(db)

      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router, true)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end

      return parent()
    end,
    DELETE = function(self, db, helpers, parent)
      rebuild_routes(db)
      return parent()
    end,

    PATCH = function(self, db, helpers, parent)
      -- create temporary router
      rebuild_routes(db)

      local ok, err = route_collision.is_route_crud_allowed(self, singletons.router)
      if not ok then
        return kong.response.exit(err.code, {message = err.message})
      end

      return parent()
    end
  },
}
