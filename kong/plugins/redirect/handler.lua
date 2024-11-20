local kong = kong
local kong_meta = require "kong.meta"
local socket_url = require "socket.url"

local RedirectHandler = {}

-- Priority 779 so that it runs after all rate limiting/validation plugins
-- and all transformation plugins, but before any AI plugins which call upstream
RedirectHandler.PRIORITY = 779
RedirectHandler.VERSION = kong_meta.version

function RedirectHandler:access(conf)
    -- Use the 'location' as-is as the default
    -- This is equivalent to conf.incoming_path == 'ignore'
    local location = conf.location

    if conf.incoming_path ~= "ignore" then
        -- Parse the URL in 'conf.location' and the incoming request
        local request_path = kong.request.get_path_with_query()
        local request_path_url = socket_url.parse(request_path)
        local location_path_url = socket_url.parse(location)

        -- The path + query are different depending on the 'incoming_path' configuration
        local path = ""
        local query = ""

        -- If incoming_path == 'keep', use the incoming request query
        if conf.incoming_path == "keep" then
            query = request_path_url.query
            path = request_path_url.path;
        end

        -- If it's 'merge', merge the incoming request path+query with the location path+query
        if conf.incoming_path == "merge" then
            -- Build the path
            path = location_path_url.path .. "/" .. request_path_url.path

            -- Build a table containing all 'location' and 'request' query parameters
            -- Overwrite the 'location' query parameters with the 'request' query parameters
            local request_path_kv = {}
            for k, v in string.gmatch(request_path_url.query, "([^&=]+)=([^&=]+)") do
                request_path_kv[k] = v
            end
            for k, v in string.gmatch(location_path_url.query, "([^&=]+)=([^&=]+)") do
                request_path_kv[k] = v
            end

            -- Rebuild the query string from the new table
            for k, v in pairs(request_path_kv) do
                query = query .. k .. "=" .. v .. "&"
            end

            -- Trim last &
            query = query:sub(1, -2)
        end

        -- Build the URL with the information
        location = socket_url.build({
            scheme = location_path_url.scheme,
            host = location_path_url.host,
            port = location_path_url.port,
            path = path,
            query = query
        })
    end

    local headers = {
        ["Location"] = location
    }
    return kong.response.exit(conf.status_code, "redirecting", headers)
end

return RedirectHandler
