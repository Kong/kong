local lapis = require "lapis"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local app_helpers = require "lapis.application"
local crud = require "kong.api.crud_helpers"


-- Initialize Lapis Application
local app = lapis.Application()


-- Instantiate a single helper object for wrapped methods
local method_helpers = {
  responses = responses,
  yield_error = app_helpers.yield_error
}


-- Create a method wrapper to pass DAO and Response helpers
-- This allows us to easily abstract routes out of this file in the future
-- by reducing the amount of externally scoped variables that are used within
-- a route method handler
local function wrap_method_handler(method_handler)
  return function(self)
    return method_handler(self, singletons.dao, method_helpers)
  end
end


-- Take routes table and iterate over each route, for each route take the
-- route's methods and wrap them with the wrap_method_handler function
local function register_routes(routes)
  for route_path, route_methods in pairs(routes) do
    local methods = {}

    for method, method_handler in pairs(route_methods) do
      methods[method] = wrap_method_handler(method_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end


-- Register application defaults
app.handle_404 = function(self)
  return responses.send_HTTP_NOT_FOUND()
end


app.handle_error = function(self, err, trace)
  if err and string.find(err, "don't know how to respond to", nil, true) then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return responses.send_HTTP_INTERNAL_SERVER_ERROR()
end


-- Declare routing object
register_routes({
  ['/files'] = {
    GET = function(self, dao_factory, helpers)
      crud.paginated_set(self, dao_factory.portal_files)
    end,
  },

  ["/files/unauthenticated"] = {
    -- List all unauthenticated files stored in the portal file system
    GET = function(self, dao_factory, helpers)
      self.params = {
        auth = false
      }

      crud.paginated_set(self, dao_factory.portal_files)
    end
  },

  ['/files/*'] = {
    before = function(self, dao_factory, helpers)
      local dao = dao_factory.portal_files
      local identifier = self.params.splat

      -- Find a file by id or field "name"
      local rows, err = crud.find_by_id_or_field(dao, {}, identifier, "name")
      if err then
        return helpers.yield_error(err)
      end

      -- Since we know both the name and id of portal_files are unique
      self.params.file_name_or_id = nil
      self.portal_file = rows[1]
      if not self.portal_file then
        return helpers.responses.send_HTTP_NOT_FOUND(
          "No file found by name or id '" .. identifier .. "'"
        )
      end
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.portal_file)
    end,
  }
})

return app
