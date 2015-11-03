local responses = require "kong.tools.responses"

local _M = {}

function _M.get_usage(api_id, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for name, limit in pairs(limits) do
    local current_metric, err = dao.ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, name)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    -- What is the current usage for the configured limit name?
    local current_usage = current_metric and current_metric.value or 0
    local remaining = limit - current_usage

    -- Recording usage
    usage[name] = {
      limit = limit,
      remaining = remaining
    }

    if remaining <= 0 then
      stop = name
    end
  end

  return usage, stop
end

return _M
