local migrate_route = require "kong.db.migrations.migrate_regex_280_300".migrate_route

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
    migrate_route(route)
  end
end
