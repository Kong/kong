local rbac       = require "kong.rbac"
local responses  = require "kong.tools.responses"
local singletons = require "kong.singletons"


local _M = {}


local function validate_filter(lapis)
  -- default route means either a silent redirect or a non-existent resource
  if lapis.route_name == "default_route" then
    return
  end

  if not singletons.configuration.enforce_rbac then
    return
  end

  local rbac_auth_header = singletons.configuration.rbac_auth_header

  local valid, err = rbac.validate(lapis.req.headers[rbac_auth_header],
                                   lapis.route_name, ngx.req.get_method(),
                                   singletons.dao)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  if not valid then
    return responses.send_HTTP_UNAUTHORIZED()
  end

  return
end
_M.validate_filter = validate_filter


return _M
