-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces = require "kong.workspaces"

local pl_template = require "pl.template"
local tablex = require "pl.tablex"
local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local runloop = require "kong.runloop.handler"


local find    = string.find
local format  = string.format
local ngx_log = ngx.log
local DEBUG   = ngx.DEBUG
local ERR     = ngx.ERR
local next    = next
local pairs = pairs
local ipairs = ipairs
local type = type
local null = ngx.null
local tostring = tostring
local match = string.match


local route_collision = {}


local ALL_METHODS = "GET,POST,PUT,DELETE,OPTIONS,PATCH"


local values = tablex.values


local function map(f, t)
  local r = {}
  local n = 0
  for _, x in ipairs(t) do
    n = n + 1
    r[n] = f(x)
  end
  return r
end


-- helper function for permutations
local function inc(t, pos)
  if t[pos][2] == #t[pos][1] then
    if pos == 1 then
      return nil
    end

    t[pos][2] = 1
    return inc(t, pos-1)

  else
    t[pos][2] = t[pos][2] + 1
    return true
  end
end


-- returns a permutations iterator using the "odometer" algorithm.
-- Example usage:
-- for i in permutations({1,2} , {3,4}) do
--   print(i[1], i[2])
-- end
local function permutations(...)

  local sets = {...}
  -- create tuples of {elements, curr_pos}
  local state = map(function(x) return {x, 1} end, sets)

  -- prepare last index to be increased on the first iteration
  state[#state][2] = 0

  local curr = #state -- first thing to increment is the last set

  return function()
    if inc(state, curr) then
      return map(function(s) return s[1][s[2]] end, state)
    else
      return nil
    end
  end
end


local function any(pred, t)
  local r
  for _, v in ipairs(t) do
    r = pred(v)
    if r then
      return r
    end
  end
  return false
end


local function member(elem, t)
  return any(function(x) return x == elem end, t)
end


local function is_wildcard(host)
  return find(host, "*") and true
end


local function is_wildcard_route(route)
  return any(is_wildcard, route.hosts)
end


local function is_blank(t)
  return not t or (type(t) == "table" and not t[1])
end



local function match_route(router, method, uri, host, sni, headers)
  return router:select(method, uri, host, nil, nil, nil, nil, nil, sni, headers)
end


-- return true if a route with method,path,host can be added in the
-- workspace ws in the current router. See
-- Workspaces-Design-Implementation quip doc for further detail.
local function validate_route_for_ws(router, method, uri, host, sni,
                                     headers, ws)
  local selected_route = match_route(router, method, uri, host, sni, headers)

  ngx_log(DEBUG, "selected route is " .. tostring(selected_route))
  if selected_route == nil then -- no match ,no conflict
    ngx_log(DEBUG, "no selected_route")
    return true

  elseif selected_route.route.ws_id == ws.id then -- same workspace
    ngx_log(DEBUG, "selected_route in the same ws")
    return true

  elseif is_blank(selected_route.route.hosts) or
    selected_route.route.hosts == null then -- we match from a no-host route
    ngx_log(DEBUG, "selected_route has no host restriction")
    return false

  elseif is_wildcard_route(selected_route.route) then -- has host & it's wildcard

    -- we try to add a wildcard
    if host and is_wildcard(host) and member(host, selected_route.route.hosts) then
      -- ours is also wildcard
      return false
    else
      return true
    end

  elseif host ~= nil then       -- 2.c.ii.1.b
    ngx_log(DEBUG, "host is not nil we collide with other")
    return false

  else -- different ws, selected_route has host and candidate not
    ngx_log(DEBUG, "different ws, selected_route has host and candidate not")
    return true
  end

end


-- workarounds for
-- https://github.com/stevedonovan/Penlight/blob/master/tests/test-stringx.lua#L141-L145
local function split(str_or_tbl)
  if type(str_or_tbl) == "table" then
    return str_or_tbl
  end

  local separator = ""
  if str_or_tbl and str_or_tbl ~= "" then
    separator = ","
  end

  return utils.split(str_or_tbl or " ", separator)
end


local function sanitize_route_param(param)
  if (param == cjson.null) or (param == null) or
    not param or "table" ~= type(param) or
    not next(param) then
    return {[""] = ""}
  else
    return param
  end
end


local function sanitize_routes_ngx_nulls(methods, paths, headers, snis)
  return
    sanitize_route_param(type(methods) == "string" and { methods } or methods),
    sanitize_route_param(type(paths) == "string" and { paths } or paths),
    sanitize_route_param(headers),
    sanitize_route_param(type(snis) == "string" and { snis } or snis)
end


-- Extracts parameters for a route to be validated against the global
-- current router. An api can have 0..* of each hosts, uris, methods.
-- We check if a route collides with the current setup by trying to
-- match each one of the combinations of accepted [hosts, uris,
-- methods]. The function returns false iff none of the variants
-- collide.
local function is_route_crud_allowed_smart(req, router)
  router = router or runloop.get_router()
  local args = req.args and req.args.post or {}

  local methods, uris, headers, snis

  local route_id_or_name = req.params.routes
  local ws = workspaces.get_workspace()
  if route_id_or_name then
    if type(route_id_or_name) == "table" then
      local encoded = cjson.encode(route_id_or_name)
      ngx_log(DEBUG, "error selecting route: ", encoded)
      return false, {
        code = 400,
        message = "Invalid query params: routes ('" ..
            encoded .. "') is of type object. Expected a string for a Route id or name",
      }
    end

    local route, route_err

    if utils.is_valid_uuid(route_id_or_name) then
      route, route_err = kong.db.routes:select({ id = route_id_or_name })
      
    else
      route, route_err = kong.db.routes:select_by_name(route_id_or_name, { workspace = ws.id })
    end
    if route_err then
      ngx_log(DEBUG, "error selecting route: " .. route_err)
      return false, {
        code = 404,
        message = "route not found with id or name = '" .. route_id_or_name .. "'",
      }
    end

    methods, uris, headers, snis = sanitize_routes_ngx_nulls(
      args.methods or (route and route.methods),
      args.paths or (route and route.paths),
      args.headers or (route and route.headers),
      args.snis or (route and route.snis)
    )

  else
    methods, uris, headers, snis = sanitize_routes_ngx_nulls(
      args.methods, args.paths, args.headers, args.snis
    )
  end

  --[[
    Retrieve the hosts from the method body of args

    NOTE: PATCH, POST, and PUT all populate req.args.post table
  --]]
  local hosts = args.hosts
  hosts = sanitize_route_param(type(hosts) == "string" and { hosts } or hosts)

  for perm in permutations(methods and values(methods) or split(ALL_METHODS),
                           uris and values(uris) or {"/"},
                           hosts and values(hosts) or {""},
                           snis and values(snis) or {""}) do
    if type(perm[1]) ~= "string" or
       type(perm[2]) ~= "string" or
       type(perm[3]) ~= "string" or
       type(perm[4]) ~= "string" then
         return true -- we can't check for collisions. let the
                      -- schema validator handle the type error
    end

    if not validate_route_for_ws(
      router, perm[1], perm[2], perm[3], perm[4], headers, ws
    ) then
      ngx_log(DEBUG, "route collided")
      return false, { code = 409,
                      message = "API route collides with an existing API",
                      collision = null }
    end
  end
  return true
end


local compiled_template_cache
local function validate_path_with_regexes(path, pattern)

  local compiled_template = compiled_template_cache
  if not compiled_template then
    compiled_template = pl_template.compile(pattern)
    compiled_template_cache = compiled_template
  end

  local ws = workspaces.get_workspace()

  local pat = compiled_template:render({
    workspace = ws.name:gsub("[-.]", "%%%1")
  })

  if not match(path, format("^%s$", pat)) then
    -- the workspace shouldn't be escaped for the error message
    local unescaped_pat = compiled_template:render({
      workspace = ws.name
    })
    return false,
    format("invalid path: '%s' (should match pattern '%s')", path, unescaped_pat)
  end

  return true
end

local function validate_paths(self, _, is_create)
  local pattern = kong.configuration.enforce_route_path_pattern
  local paths = self.params.paths

  if (is_create and not paths) or paths == null then
    return false, { code = 400,
                    message = format("path is required matching pattern '%s')", pattern),
                    collision = null }
  end

  if type(paths) ~= "table" then
    paths = { paths }
  end

  for _, path in pairs(paths) do
    local ok, err = validate_path_with_regexes(path, pattern)
    if not ok then
      return false, { code = 400,
                     message = err,
                     collision = null }
    end
  end

  return true
end


local function validate_static(req, _, is_create)
  local paths = req.args and req.args.post and req.args.post.paths
  paths = sanitize_route_param(type(paths) == "string" and { paths } or paths)

  local methods = req.args and req.args.post and req.args.post.methods
  methods = sanitize_route_param(type(methods) == "string" and { methods } or methods)

  local hosts = req.args and req.args.post and req.args.post.hosts
  hosts = sanitize_route_param(type(hosts) == "string" and { hosts } or hosts)

  local res, err, _ = kong.db.routes:check_route_overlap(paths, hosts, methods, req.params.routes)
  if not res then
    ngx_log(ERR, "route collision error: ", err)
    return false, { code = 500, message = "Error while checking route collision" }

  elseif #res > 0 then
    local route = res[1]
    return false, { code = 409,
                    message = format("API route collides with an existing route: id=%s, name=%s, service_id=%s, workspace_id=%s",
                      route.id, route.name, route.service and route.service.id or null, route.ws_id),
                    collision = {
                      request = {
                        paths = paths and #paths > 0 and paths or null,
                        methods = methods and #methods > 0 and methods or null,
                        hosts = hosts and #hosts > 0 and hosts or null,
                      },
                      existing_route = route
                    }
                  }
  end

  return true
end


local route_collision_strategies = {
  off = function() return true end,
  smart = is_route_crud_allowed_smart,
  path = validate_paths,
  static = validate_static
}


function route_collision.is_route_crud_allowed(req, router, is_create)
  local strategy = kong.configuration.route_validation_strategy
  return route_collision_strategies[strategy](req, router, is_create)
end


-- for unit testing purposes only
route_collision._match_route = match_route
route_collision._validate_route_for_ws = validate_route_for_ws
route_collision._permutations = permutations


return route_collision
