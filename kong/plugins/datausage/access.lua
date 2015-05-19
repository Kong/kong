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

  local least_remaining_limit

  for _, period_conf in ipairs(conf.limit) do
    local period, period_limit = unpack(stringy.split(period_conf, ":"))

    period_limit = tonumber(period_limit)
    -- Load metric for configured period
    local period_metric, err = dao.datausage_metrics:find_one(ngx.ctx.api.id, identifier, current_timestamp, period)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(stmt_err)
    end

    -- What is the usage for the configured period?
    local period_usage = period_metric and period_metric.value or 0

    local period_remaining = period_limit - period_usage

    -- Figure out the period, which has the least remaining calls left
    if not least_remaining_limit or period_remaining < least_remaining_limit then
      least_remaining_limit = period_remaining
    end

    -- Set the reamining limit of this period in the header
    ngx.header[constants.HEADERS.DATAUSAGE_LIMIT:gsub("<duration>", period:gsub("^%l", string.upper))] = period_limit
    ngx.header[constants.HEADERS.DATAUSAGE_REMAINING:gsub("<duration>", period:gsub("^%l", string.upper))] = math.max(0, period_remaining - 1) -- -1 for this period request
  end

  if least_remaining_limit <= 0 then
    ngx.ctx.stop_phases = true -- interrupt other phases of this request
    return responses.send(429, "API rate limit exceeded")
  end

end

return _M


