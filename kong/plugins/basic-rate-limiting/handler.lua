-- Copyright (C) Kong Inc.
local kong_meta = require "kong.meta"

local kong = kong
local ngx = ngx
local shm = ngx.shared.kong_rate_limiting_counters

local BasicRateLimitingHandler = {}

BasicRateLimitingHandler.VERSION = kong_meta.version
BasicRateLimitingHandler.PRIORITY = 911

function BasicRateLimitingHandler:access(conf)
    local counter = shm:incr("BasicRateLimiting",1,0,60)

    -- If limit is exceeded, terminate the request
    if counter > conf.minute then
        return kong.response.error(conf.error_code, conf.error_message)
    end
    
end

return BasicRateLimitingHandler