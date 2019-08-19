local workspaces = require "kong.workspaces"
local lyaml      = require "lyaml"
local file_helpers = require "kong.portal.file_helpers"
local ts_helpers   = require "kong.portal.render_toolset.helpers"


local EXTENSION_LIST = file_helpers.content_extension_list
local yaml_load = lyaml.load


local router_item_map = {
  ["url"]         = true,
  ["auth"]        = true,
  ["layout"]      = true,
  ["readable_by"] = true,
  ["has_content"] = true,
}


local function is_route_priority(ws_router, route, path)
  if not ws_router[route] then
    return true
  end

  local route_conf = ws_router[route]
  if route_conf.url then
    return false, 'route ' .. route .. ' locked.'
  end

  local path_attrs   = ts_helpers.get_file_attrs_by_path(path)
  local r_path_attrs = ts_helpers.get_file_attrs_by_path(route_conf.path)
  if path_attrs.priority > r_path_attrs.priority then
    return false, 'route already set with highest priority'
  end

  return true
end


local function get_ws_router(router, ws)
  if not ws then
    ws = workspaces.get_workspace()
  end
  local ws_name = ws.name

  if not router[ws_name] then
    router[ws_name] = {}
  end

  return router[ws_name]
end


local function build_route_item(file)
  local parsed_config = yaml_load(file.contents)
  if not parsed_config or not next(parsed_config) then
    return { has_content = false }
  end

  local router_item = {}
  for k, v in pairs(parsed_config) do
    if router_item_map[k] then
      router_item[k] = parsed_config[k]
    else
      router_item.has_content = true
    end
  end

  router_item.path = file.path

  return router_item
end


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


local function reset_route_ctx_by_file(db, ws_router, file)
  local route = ts_helpers.get_route_from_path(file.path)
  if not route then
    return
  end

  local r_file = find_highest_priority_file_by_route(db, route)
  if not r_file then
    ws_router[route] = nil
    return
  end

  ws_router[route] = build_route_item(r_file)
end


local function set_route_ctx_by_file(ws_router, file)
  local route = ts_helpers.get_route_from_path(file.path)
  local is_priority = is_route_priority(ws_router, route, file.path)
  if route and is_priority then
    local route_conf = build_route_item(file)
    if route_conf.url then
      route = route_conf.url
    end

    ws_router[route] = route_conf
  end
end


local function get_route_ctx_by_route(ws_router, route)
  if ws_router.static then
    local route_ctx = ws_router[route]

    if not route_ctx then
      route_ctx = ws_router["/*"]
    end

    if not route then
      route_ctx = {}
    end

    return route_ctx
  end

  return ws_router[route] or {}
end


local function set_custom_router(db, ws_router, router_conf)
  local custom_router = yaml_load(router_conf.contents)
  for route, path in pairs(custom_router) do
    local file = db.files:select_by_path(path)
    ws_router[route] = build_route_item(file)
  end

  ws_router.static = true

  return ws_router
end


local function rebuild_ws_router(db, ws_router)
  local router_conf = db.files:select_by_path("router.conf.yaml")
  if router_conf then
    return set_custom_router(db, ws_router, router_conf)
  end

  local files = db.files:select_all()
  for i, file in ipairs(files) do
    reset_route_ctx_by_file(db, ws_router, file)
  end
end


return {
  new = function(db)
    local router = {}

    return {
      find_highest_priority_file_by_route = find_highest_priority_file_by_route,
      get_route_ctx_by_route = function(route)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          rebuild_ws_router(db, ws_router)
        end

        return get_route_ctx_by_route(ws_router, route)
      end,

      set_route_ctx_by_file = function(file)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          rebuild_ws_router(db, ws_router)
        end

        if ws_router.static then
          return
        end

        return set_route_ctx_by_file(ws_router, file)
      end,

      reset_route_ctx_by_file = function(file)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          rebuild_ws_router(db, ws_router)
        end

        if ws_router.static then
          return
        end

        return reset_route_ctx_by_file(db, ws_router, file)
      end,

      set_custom_router = function(file)
        -- XXX Linter complaining about reassignment of ws_router before accessing initial assignment
        -- Not sure if we want empty table or call to get_ws_router?
        -- local ws_router = get_ws_router(router)
        local ws_router = {}

        return set_custom_router(db, ws_router, file)
      end,

      delete_custom_router = function()
        -- XXX Linter complaining about reassignment of ws_router before accessing initial assignment
        -- Not sure if we want empty table or call to get_ws_router?
        -- local ws_router = get_ws_router(router)
        local ws_router = {}

        return rebuild_ws_router(db, ws_router)
      end,

      get_ws_router = function(workspace)
        local ws_router = get_ws_router(router)
        if not ws_router or not next(ws_router) then
          rebuild_ws_router(db, ws_router)
        end

        return ws_router
      end,
    }
  end
}
