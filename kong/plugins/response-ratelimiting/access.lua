local policies = require "kong.plugins.response-ratelimiting.policies"
local timestamp = require "kong.tools.timestamp"

local pairs = pairs
local tostring = tostring


local HTTP_INTERNAL_SERVER_ERROR = 500
local HTTP_TOO_MANY_REQUESTS = 429


local function get_ctx(k)
  local v = kong.ctx.shared[k] -- forward compatibility
  if v ~= nil then
    return v
  end
  return ngx.ctx[k] -- backward compatibility
end


local _M = {}

local RATELIMIT_REMAINING = "X-RateLimit-Remaining"

local function get_identifier(conf)
  if conf.limit_by == "ip" then
    return kong.client.get_forwarded_ip()
  end

  -- Consumer is identified by ip address or authenticated_credential id
  if conf.limit_by == "consumer" then
    local authenticated_consumer = get_ctx("authenticated_consumer")
    local identifier = authenticated_consumer and authenticated_consumer.id
    if identifier then
      return identifier
    end
  end

  -- Fallback on credential
  local authenticated_credential = get_ctx("authenticated_credential")
  local identifier = authenticated_credential and authenticated_credential.id
  if identifier then
    return identifier
  end

  return kong.client.get_forwarded_ip()
end

local function get_usage(conf, identifier, current_timestamp, limits)
  local usage = {}

  for k, v in pairs(limits) do -- Iterate over limit names
    for lk, lv in pairs(v) do -- Iterare over periods
      local current_usage, err = policies[conf.policy].usage(conf, identifier, current_timestamp, lk, k)
      if err then
        return nil, err
      end

      local remaining = lv - current_usage

      if not usage[k] then
        usage[k] = {}
      end
      if not usage[k][lk] then
        usage[k][lk] = {}
      end

      usage[k][lk].limit = lv
      usage[k][lk].remaining = remaining
    end
  end

  return usage
end

function _M.execute(conf)
  if not next(conf.limits) then
    return
  end

  -- Load info
  local current_timestamp = timestamp.get_utc()
  kong.ctx.plugin.current_timestamp = current_timestamp -- For later use
  local identifier = get_identifier(conf)
  kong.ctx.plugin.identifier = identifier -- For later use

  -- Load current metric for configured period
  local usage, err = get_usage(conf, identifier, current_timestamp, conf.limits)
  if err then
    if conf.fault_tolerant then
      kong.log.err("failed to get usage: ", tostring(err))
      return
    else
      return kong.response.exit(HTTP_INTERNAL_SERVER_ERROR, {
        message = "An unexpected error occurred"
      })
    end
  end

  -- Append usage headers to the upstream request. Also checks "block_on_first_violation".
  for k, v in pairs(conf.limits) do
    local remaining
    for lk, lv in pairs(usage[k]) do
      if conf.block_on_first_violation and lv.remaining == 0 then
        return kong.response.exit(HTTP_TOO_MANY_REQUESTS, {
          message = "API rate limit exceeded for '" .. k .. "'"
        })
      end

      if not remaining or lv.remaining < remaining then
        remaining = lv.remaining
      end
    end

    kong.service.request.set_header(RATELIMIT_REMAINING .. "-" .. k, remaining)
  end

  kong.ctx.plugin.usage = usage -- For later use
end

return _M
