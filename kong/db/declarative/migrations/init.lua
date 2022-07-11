local regex_route_path = require "kong.db.declarative.migrations.regex_route_path"

return function (entities, meta)
    if not meta then
        -- we can not migrate without version specified
        return
    end

    if not entities then
        -- no need to migrate
        return
    end

    regex_route_path(entities, meta._format_version)
end
