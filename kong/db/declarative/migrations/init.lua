local regex_route_path = require "kong.db.declarative.migrations.regex_route_path"

return function (tbl)
    if not tbl then
        -- we can not migrate without version specified
        return
    end

    regex_route_path(tbl)

    tbl._format_version = "3.0"
end
