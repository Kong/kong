local kong = kong
local kong_meta = require "kong.meta"
local ada = require "resty.ada"

local RedirectHandler = {}

-- Priority 779 so that it runs after all rate limiting/validation plugins
-- and all transformation plugins, but before any AI plugins which call upstream
RedirectHandler.PRIORITY = 779
RedirectHandler.VERSION = kong_meta.version

function RedirectHandler:access(conf)
    -- Use the 'location' as-is as the default
    -- This is equivalent to conf.incoming_path == 'ignore'
    local location = conf.location

    if conf.keep_incoming_path then
        -- Parse the URL in 'conf.location' and the incoming request
        local location_url = ada.parse(location)

        -- Overwrite the path in 'location' with the path from the incoming request
        location = location_url:set_pathname(kong.request.get_path()):set_search(kong.request.get_raw_query()):get_href()
    end

    local headers = {
        ["Location"] = location
    }

    return kong.response.exit(conf.status_code, "redirecting", headers)
end

return RedirectHandler
