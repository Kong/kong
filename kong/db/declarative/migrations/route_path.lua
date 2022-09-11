local migrate_path = require "kong.db.migrations.migrate_path_280_300"

return function(tbl, version)
  if not tbl or not (version == "1.1" or version == "2.1") then
    return
  end

  local routes = tbl.routes

  if not routes then
    -- no need to migrate
    return
  end

  for _, route in pairs(routes) do
    local paths = route.paths
    if not paths or paths == ngx.null then
      -- no need to migrate
      goto continue
    end

    for idx, path in ipairs(paths) do
      paths[idx] = migrate_path(path)
    end

    ::continue::
  end
end
