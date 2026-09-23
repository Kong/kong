local route_path = require "kong.db.declarative.migrations.route_path"

return function(tbl)
  if not tbl then
    -- we can not migrate without version specified
    return
  end

  route_path(tbl, tbl._format_version)

  tbl._format_version = "3.0"
end
