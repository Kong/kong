local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local stringy = require "stringy"

local _M = {}

function _M.execute(conf)
  local current_timestamp = timestamp.get_utc()

  -- Consumer is identified by ip address or authenticated_entity id
  local identifier
  if ngx.ctx.authenticated_entity then
    identifier = ngx.ctx.authenticated_entity.id
  else
    identifier = ngx.var.remote_addr
  end

  local periods_and_limits = {}x
  for _,v in ipairs(conf.limit) do
     local parts = stringy.split(v, ":")
     periods_and_limits[parts[1]] = parts[2]
  end

  local least_remaining_limit = 99999999 -- A huge number so that any limit will be actually less than this

  for period, limit in pairs(periods_and_limits) do
    limit = tonumber(limit)
    -- Load current metric for configured period
    local current_metric, err = dao.ratelimiting_metrics:find_all_periods(ngx.ctx.api.id, identifier, current_timestamp, period)
    if err then
      ngx.log(ngx.ERR, tostring(err))
      utils.show_error(500)
    end

    -- What is the current usage for the configured period?
    local current_usage
    if current_metric ~= nil then
      current_usage = current_metric.value
    else
      current_usage = 0
    end
    
    local remaining = limit - current_usage

    -- Figure out the period, which has the least remaining calls left
    if remaining < least_remaining_limit then
       least_remaining_limit = remaining
    end

    -- Set the least reamining limit period in the header
    ngx.header[constants.HEADERS.RATELIMIT_LIMIT.."-"..period.upper] = limit
    ngx.header[constants.HEADERS.RATELIMIT_REMAINING.."-"..period.upper] = math.max(0, remaining - 1) -- -1 for this current request
  end

  if least_remaining_limit <= 0 then
     utils.show_error(429, "API rate limit exceeded")
  end 

  -- Increment metrics for all periods if the request goes through
  local _, stmt_err = dao.ratelimiting_metrics:increment(ngx.ctx.api.id, identifier, current_timestamp)
  if stmt_err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(stmt_err)
  end
end

return _M
