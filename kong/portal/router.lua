local file_helpers = require "kong.portal.file_helpers"
local workspaces   = require "kong.workspaces"
local constants    = require "kong.constants"

local EXTENSION_LIST = constants.PORTAL_RENDERER.EXTENSION_LIST
local ROUTE_TYPES    = constants.PORTAL_RENDERER.ROUTE_TYPES


local function is_route_priority(content_router, route_item)
  local route = route_item.route
  if not content_router[route] then
    return true
  end

  local route_conf = content_router[route]
  if route_conf.explicit then
    return false, 'route ' .. route .. ' locked.'
  end

  local current_path_meta = route_conf.path_meta
  local incoming_path_meta  = route_item.path_meta
  if current_path_meta.priority < incoming_path_meta.priority then
    return false, 'route already set with highest priority'
  end

  return true
end


-- Iterates through file name possibilities by file extentsion priority.
local function find_highest_priority_file_by_route(db, route)
  local file
  for _, v in ipairs(EXTENSION_LIST) do
    local ext = "." .. v
    local path = "content" .. route .. ext
    file = db.files:select_by_path(path)
    if file then
      return file
    end
  end

  for _, v in ipairs(EXTENSION_LIST) do
    local ext = "." .. v
    if route == "/" then
      route = ""
    end
    local path = "content" .. route .. "/index" .. ext
    file = db.files:select_by_path(path)
    if file then
      return file
    end
  end
end


local function generate_router_by_conf(db, ws_router, router_conf)
  for route, path in pairs(router_conf) do
    local file = db.files:select_by_path(path)
    ws_router[route] = file_helpers.parse_content(file)
  end

  return ws_router
end


local function generate_route(ws_router, route_item)
  local route_type = route_item.route_type
  local route = route_item.route
  if route_type == ROUTE_TYPES.EXPLICIT then
    ws_router.explicit[route] = route_item
    return
  end

  if route_type == ROUTE_TYPES.COLLECTION then
    ws_router.collection[route] = route_item
    return
  end

  local is_priority = is_route_priority(ws_router.content, route_item)
  if route and is_priority then
    ws_router.content[route] = route_item
  end
end


local function build_ws_router(db, ws_router, router_conf)
  local router_conf = file_helpers.get_conf("router")
  if router_conf then
    ws_router.custom = {}
    generate_router_by_conf(db, ws_router.custom, router_conf)
  end

  ws_router.content = ws_router.content or {}
  ws_router.explicit = ws_router.explicit or {}
  ws_router.collection = ws_router.collection or {}
  for file in db.files:each() do
    local route_item = file_helpers.parse_content(file)
    if route_item and route_item.route then
      generate_route(ws_router, route_item)
    end
  end
end


local function get_ws_router(router, ws)	-- Iterates through file name possibilities by file extentsion priority.
  if not ws then
    ws = workspaces.get_workspace()
  end
  local ws_name = ws.name

   if not router[ws_name] then
    router[ws_name] = {}
  end

  return router[ws_name]	
end


return {
  new = function(db)
    local router = {}

    return {
      find_highest_priority_file_by_route = find_highest_priority_file_by_route,

      build = function(custom_conf)
        local ws_router = get_ws_router(router)
        return build_ws_router(db, ws_router, custom_conf)
      end,

      -- Retrieve a route object via route name.  If a wildcard route exists
      -- and an alternative cannot be found, the wildcard route will be returned.
      get = function(route)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          build_ws_router(db, ws_router)
        end

        local route_obj = ws_router.explicit[route]
        if not route_obj then
          route_obj = ws_router.content[route]
        end

        if not route_obj then
          route_obj = ws_router.collection[route]
        end

        if not route_obj then
          route_obj = {}
        end

        if ws_router.custom then
          route_obj = ws_router.custom[route]
          if not route_obj then
            route_obj = ws_router.custom["/*"]
          end
      
          if not route then
            route_obj = {}
          end
        end

        return route_obj
      end,

      -- Set route object via content file.  Route will not be set if the
      -- passed content file is lower priority than a previously set file
      -- under the same resolved route.
      add_route_by_content_file = function(file)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          build_ws_router(db, ws_router)
        end

        local route_item = file_helpers.parse_content(file)
        if route_item and route_item.route then
          generate_route(ws_router, route_item)
        end
      end,

      get_ws_router = function(workspace)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          build_ws_router(db, ws_router)
        end

        return ws_router
      end,
    }
  end
}
