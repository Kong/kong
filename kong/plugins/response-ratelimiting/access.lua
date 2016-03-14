local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"

local _M = {}

local function get_identifier()
  local identifier

  -- Consumer is identified by ip address or authenticated_credential id
  if ngx.ctx.authenticated_credential then
    identifier = ngx.ctx.authenticated_credential.id
  else
    identifier = ngx.var.remote_addr
  end

  return identifier
end

local function get_current_usage(api_id, identifier, current_timestamp, limits)
  local usage = {}

  for k, v in pairs(limits) do -- Iterate over limit names
    for lk, lv in pairs(v) do -- Iterare over periods
      local current_metric, err = singletons.dao.response_ratelimiting_metrics:find(api_id, identifier, current_timestamp, lk, k)
      if err then
        return false, err
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
  local usage, err = get_current_usage(api_id, identifier, current_timestamp, conf.limits)
  if err then
    if conf.continue_on_error then
      ngx.log(ngx.ERR, "failed to get usage: ", tostring(err))
      return
    else
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end
  ngx.ctx.usage = usage -- For later use
end

return _M
