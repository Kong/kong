local migrate_regex = require "kong.db.migrations.migrate_regex_280_300"

return function(tbl)
  local version = tbl._format_version
  if not (version == "1.1" or version == "2.1") then
    return
  end

  local routes = tbl.routes

  if not routes then
    -- no need to migrate
    return
  end

  for _, route in pairs(routes) do
    local paths = route.paths
    if not paths then
      -- no need to migrate
      goto continue
    end

    for idx, path in ipairs(paths) do
      paths[idx] = migrate_regex(path)
    end

    ::continue::
  end
end
