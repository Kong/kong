local migrate_path = require "kong.db.migrations.migrate_path_280_300"

local pairs  = pairs
local ipairs = ipairs

local empty_tbl = {}

local function indexable(val)
  if type(val) == "table" then
    return true
  end

  local meta = getmetatable(val)
  return meta and meta.__index
end

local function table_default(val)
  -- we cannot verify it with type(val) == "table" because
  -- we may receive indexable cdata/lightuserdata
  if indexable(val) then
    return val

  else
    return empty_tbl
  end
end

local function migrate_routes(routes)
  for _, route in pairs(routes) do
    local paths = table_default(route.paths)

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
  local routes = table_default(tbl.routes)
  migrate_routes(routes)

  -- migrate routes nested in top-level services
  local services = table_default(tbl.services)
  for _, service in pairs(services) do
    local nested_routes = table_default(service.routes)

    migrate_routes(nested_routes)
  end

  tbl._format_version = "3.0"
end
