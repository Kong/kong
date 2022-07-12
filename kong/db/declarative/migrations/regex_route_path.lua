local migrate_regex = require "kong.db.migrations.migrate_regex_280_300"

return function(entities, version)
  if not (version == "1.1" or version == "2.1") then
    return
  end

  local routes = entities.routes

  if not (routes and next(routes)) then
    -- no need to migrate
    return
  end

  for _, route in pairs(routes) do
    local paths = route.paths
    if not (paths and next(paths)) then
      -- no need to migrate
      goto continue
    end

    for idx = 1, #paths do
      paths[idx] = migrate_regex(paths[idx])
    end

    ::continue::
  end
end
