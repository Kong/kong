local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local stringy = require "stringy"

local _M = {}

local function log(premature, conf, message)
    local current_timestamp = timestamp.get_utc()
    -- Consumer is identified by ip address or authenticated_entity id
    local identifier
    if message["authenticated_entity"] then
        identifier = message["authenticated_entity"].id
    else
        identifier = message["ip"]
    end

    for _, period_conf in ipairs(conf.limit) do
        local period, period_limit = unpack(stringy.split(period_conf, ":"))

        period_limit = tonumber(period_limit)

        -- Increment metrics for all periods if the request goes through
        local count = tonumber(message["response"]["headers"][conf.metric_counter_variable])

        local _, stmt_err = dao.datausage_metrics:increment(message["api"].id, identifier, current_timestamp, count)
        if stmt_err then
            return responses.send_HTTP_INTERNAL_SERVER_ERROR(stmt_err)
        end
    end
end

function _M.execute(conf)
    local ok, err = ngx.timer.at(0, log, conf, ngx.ctx.log_message)
    if not ok then
        ngx.log(ngx.ERR, "failed to create timer: ", err)
    end
end

return _M




