local policies = require "kong.plugins.response-ratelimiting.policies"
local timestamp = require "kong.tools.timestamp"


local kong = kong
local next = next
local pairs = pairs
local tostring = tostring


local _M = {}


local function get_identifier(conf)
  if conf.limit_by == "consumer" then
    local consumer = kong.client.get_consumer()
    if consumer and consumer.id then
      return consumer.id
    end

    local credential = kong.client.get_credential()
    if credential and credential.id then
      return credential.id
    end

  elseif conf.limit_by == "credential" then
    local credential = kong.client.get_credential()
    if credential and credential.id then
      return credential.id
    end
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

      if not usage[k] then
        usage[k] = {}
      end

      if not usage[k][lk] then
        usage[k][lk] = {}
      end

      usage[k][lk].limit = lv
      usage[k][lk].remaining = lv - current_usage
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
    kong.log.err("failed to get usage: ", tostring(err))

    if conf.fault_tolerant then
      return
    end

    return kong.response.exit(500, {
      message = "An unexpected error occurred"
    })
  end

  -- Append usage headers to the upstream request. Also checks "block_on_first_violation".
  for k in pairs(conf.limits) do
    local remaining
    for _, lv in pairs(usage[k]) do
      if conf.block_on_first_violation and lv.remaining == 0 then
        return kong.response.exit(429, {
          message = "API rate limit exceeded for '" .. k .. "'"
        })
      end

      if not remaining or lv.remaining < remaining then
        remaining = lv.remaining
      end
    end

    if remaining then
      kong.service.request.set_header("X-RateLimit-Remaining-" .. k, remaining)
    end
  end

  kong.ctx.plugin.usage = usage -- For later use
end


return _M
