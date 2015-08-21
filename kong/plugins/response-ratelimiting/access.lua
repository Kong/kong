local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"

local _M = {}

local function get_identifier()
  local identifier

  -- Consumer is identified by ip address or authenticated_entity id
  if ngx.ctx.authenticated_entity then
    identifier = ngx.ctx.authenticated_entity.id
  else
    identifier = ngx.var.remote_addr
  end

  return identifier
end

local function get_current_usage(api_id, identifier, current_timestamp, limits)
  local usage = {}

  for k, v in pairs(limits) do -- Iterate over limit names
    for lk, lv in pairs(v) do -- Iterare over periods
      local current_metric, err = dao.response_ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, lk, k)
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      local current_usage = current_metric and current_metric.value or 0
      local remaining = lv - current_usage

      if not usage[k] then usage[k] = {} end
      if not usage[k][lk] then usage[k][lk] = {} end

      usage[k][lk].limit = lv
      usage[k][lk].remaining = remaining
    end
  end

  return usage
end

function _M.execute(conf)
  if utils.table_size(conf.limits) <= 0 then
    return
  end

  -- Load info
  local current_timestamp = timestamp.get_utc() 
  ngx.ctx.current_timestamp = current_timestamp -- For later use
  local api_id = ngx.ctx.api.id
  local identifier = get_identifier()
  ngx.ctx.identifier = identifier -- For later use

  -- Load current metric for configured period
  local usage = get_current_usage(api_id, identifier, current_timestamp, conf.limits)
  ngx.ctx.usage = usage -- For later use
end

return _M
