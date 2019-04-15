local kong = kong
local crud = require "kong.api.crud_helpers"
local utils = require "kong.tools.utils"
local reports = require "kong.reports"
local endpoints = require "kong.api.endpoints"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local ApiRouter = require "kong.api_router"
local core_handler = require "kong.runloop.handler"


local function filter(pred, t)
  local res = {}
  for _, v in ipairs(t) do
    if pred(v) then
      res[#res+1] = v
    end
  end
  return res
end


-- returns all routes except the current one
local function all_apis_except(current)
  local old_wss = ngx.ctx.workspaces
  ngx.ctx.workspaces = {}
  local apis = singletons.dao.apis:find_all()
  apis = filter(function(x) return x.id ~= current.id end, apis)
  ngx.ctx.workspaces = old_wss
  return apis
end


local get_api_plugin = endpoints.get_collection_endpoint(kong.db.plugins.schema,
                                                         kong.db.apis.schema,
                                                         "api")
local post_api_plugin = endpoints.post_collection_endpoint(kong.db.plugins.schema,
                                                           kong.db.apis.schema,
                                                           "api")


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "a"
  reports.send("api", r_data)
  return data
end


return {
  ["/apis/"] = {
    before = function(self, dao_factory, helpers)
      local uuid = require("kong.tools.utils").uuid
      local old_wss = ngx.ctx.workspaces
      ngx.ctx.workspaces = {}
      core_handler.build_api_router(dao_factory, uuid())
      ngx.ctx.workspaces = old_wss
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.apis)
    end,

    -- XXX: DO NOT add helpers as a third parameter. It collides with
    -- CE and makes merges difficult
    PUT = function(self, dao_factory)
      -- if no id, it acts as POST
      if not self.params.id and workspaces.is_api_colliding(self) then
        local err = "API route collides with an existing API"
        return kong.respnse.exit(409, { message = err })
      end

      if self.params.id then
        local curr_api = singletons.dao.apis:find({id = self.params.id})
        if curr_api then  -- exists, we create an ad-hoc router

          local r = ApiRouter.new(all_apis_except(curr_api))
          if workspaces.is_api_colliding(self, r) then
            local err = "API route collides with an existing API"
            return kong.respnse.exit(409, { message = err })
          end
        end
      end

      crud.put(self.params, dao_factory.apis)
    end,

    POST = function(self, dao_factory)
      if workspaces.is_api_colliding(self) then
        local err = "API route collides with an existing API"
        return kong.respnse.exit(409, { message = err })
      end
      crud.post(self.params, dao_factory.apis)
    end
  },

  ["/apis/:api_name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_api_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return kong.respnse.exit(200,  self.api)
    end,

    -- XXX: DO NOT add helpers as a third parameter. It collides with
    -- CE and makes merges difficult
    PATCH = function(self, dao_factory)
      local r = ApiRouter.new(all_apis_except(self.api))
      -- create temporary router
      if workspaces.is_api_colliding(self, r) then
        local err = "API route collides with an existing API"
        return kong.respnse.exit(409, {message = err})
      end

      crud.patch(self.params, dao_factory.apis, self.api)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api, dao_factory.apis)
    end
  },

  ["/apis/:apis/plugins/"] = {
    GET = function(self, dao, helpers)
      return get_api_plugin(self, dao.db.new_db, helpers)
    end,

    POST = function(self, dao, helpers)
      return post_api_plugin(self, dao.db.new_db, helpers, post_process)
    end
  },

}
