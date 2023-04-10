local declarative = require "kong.db.declarative"

local tonumber = tonumber
local kong = kong

local get_current_hash = declarative.get_current_hash

local constants = require "kong.constants"

local worker_count = ngx.worker.count()
local kong_shm = ngx.shared.kong
local is_traditional = kong.configuration.database ~= "off"

local DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY = 
                              constants.DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY
local DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY =
                              constants.DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY
local DECLARATIVE_EMPTY_CONFIG_HASH =
                              constants.DECLARATIVE_EMPTY_CONFIG_HASH

function is_ready()

    local ok = kong.db:connect()
    if not ok then
        return false
    end

    if is_traditional then
        kong.db:close() -- ignore ERRs
        return true
    end

    local router_rebuilds = 
            tonumber(kong_shm:get(DECLARATIVE_ROUTERS_REBUILD_COUNT_KEY)) or 0
    local plugins_iterator_rebuilds = 
            tonumber(kong_shm:get(DECLARATIVE_PLUGINS_REBUILD_COUNT_KEY)) or 0

    if router_rebuilds < worker_count 
      or plugins_iterator_rebuilds < worker_count
    then
        return false
    end

    local current_hash = get_current_hash()

    if not current_hash or current_hash == DECLARATIVE_EMPTY_CONFIG_HASH then
        return false
    end

    return true
end

return {
    ["/status/ready"] = {
        GET = function(self, dao, helpers)
            if is_ready() then
                return kong.response.exit(200, 'ready')
            else
                return kong.response.exit(503, 'not ready')
            end
        end
    }
}
