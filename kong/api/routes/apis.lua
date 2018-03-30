local crud    = require "kong.api.crud_helpers"
local utils   = require "kong.tools.utils"
local reports = require "kong.core.reports"
local workspaces = require "kong.workspaces"
local app_helpers = require "lapis.application"
local singletons = require "kong.singletons"
local Router = require "kong.core.router"
local core_handler = require "kong.core.handler"

return {
  ["/apis/"] = {

    before = function(self, dao_factory, helpers)
      local uuid = require("kong.tools.utils").uuid
      local version, err = singletons.cache:get("router:version", {
        ttl = 0
      }, function() return utils.uuid() end)
      if err then
        ngx.log(ngx.CRIT, "could not ensure router is up to date: ", err)

      elseif true or router_version ~= version then
        -- router needs to be rebuilt in this worker
        ngx.log(ngx.DEBUG, "rebuilding router")
        local old_ws = ngx.ctx.workspace
        ngx.ctx.workspace = {name = "*"}

        local ok, err = core_handler.build_router(singletons.dao, uuid())

        ngx.ctx.workspace = old_ws
        if not ok then
          ngx.log(ngx.CRIT, "could not rebuild router: ", err)
        end
      end

      local old_ws = ngx.ctx.workspace
      ngx.ctx.workspace = {name = "*"}
      core_handler.build_router(dao_factory, uuid())
      ngx.ctx.workspace = old_ws
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.apis)
    end,

    PUT = function(self, dao_factory)
      -- TODO: check when doing updates.  Probably have to remove the
      -- route from the router before running the check.
      crud.put(self.params, dao_factory.apis)
    end,

    POST = function(self, dao_factory, helpers)
      if workspaces.is_route_colliding(self) then
        local err = "API route collides with an existing API"
        return helpers.responses.send_HTTP_CONFLICT(err)
      end
      crud.post(self.params, dao_factory.apis)
    end
  },

  ["/apis/:api_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.apis, self.api)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api, dao_factory.apis)
    end
  },

  ["/apis/:api_name_or_id/plugins/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      self.params.api_id = self.api.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.plugins)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.plugins, function(data)
        local r_data = utils.deep_copy(data)
        r_data.config = nil
        reports.send("api", r_data)
      end)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.plugins)
    end
  },

  ["/apis/:api_name_or_id/plugins/:id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
      crud.find_plugin_by_filter(self, dao_factory, {
        api_id = self.api.id,
        id     = self.params.id,
      }, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.plugin)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.plugins, self.plugin)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.plugin, dao_factory.plugins)
    end
  }
}
