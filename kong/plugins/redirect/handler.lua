-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local kong_meta = require "kong.meta"
local ada = require "resty.ada"

local RedirectHandler = {}

-- Priority 779 so that it runs after all rate limiting/validation plugins
-- and all transformation plugins, but before any AI plugins which call upstream
RedirectHandler.PRIORITY = 779
RedirectHandler.VERSION = kong_meta.core_version

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
