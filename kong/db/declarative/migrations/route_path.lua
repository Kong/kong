local migrate_path = require "kong.db.migrations.migrate_path_280_300"
local lyaml_null = require("lyaml").null
local cjson_null = require("cjson").null

local ngx_null = ngx.null
local pairs  = pairs
local ipairs = ipairs

local EMPTY = {}

local function ensure_table(val)
  if val == nil or val == ngx_null or val == lyaml_null or val == cjson_null or type(val) ~= "table" then
    return EMPTY
  end
  return val
end

local function migrate_routes(routes)
  for _, route in pairs(routes) do
    local paths = ensure_table(route.paths)

    for idx, path in ipairs(paths) do
      paths[idx] = migrate_path(path)
    end
  end
end

return function(tbl)
  local version = tbl._format_version
  if not tbl or not (version == "1.1" or version == "2.1") then
    return
  end

  -- migrate top-level routes
  local routes = ensure_table(tbl.routes)
  migrate_routes(routes)

  -- migrate routes nested in top-level services
  local services = ensure_table(tbl.services)
  for _, service in ipairs(services) do
    local nested_routes = ensure_table(service.routes)

    migrate_routes(nested_routes)
  end

  tbl._format_version = "3.0"
end
