-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong_string = require "kong.tools.string"
local pdk_private_rl = require "kong.pdk.private.rate_limiting"


local kong = kong
local next = next
local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local math_max = math.max


local strip = kong_string.strip
local split = kong_string.split
local pdk_rl_set_response_headers = pdk_private_rl.set_response_headers
local pdk_rl_set_limit_by_with_identifier = pdk_private_rl.set_limit_by_with_identifier


local function parse_header(header_value, limits)
  local increments = {}

  if header_value then
    local parts
    if type(header_value) == "table" then
      parts = header_value
    else
      parts = split(header_value, ",")
    end

    for _, v in ipairs(parts) do
      local increment_parts = split(v, "=")
      if #increment_parts == 2 then
        local limit_name = strip(increment_parts[1])
        if limits[limit_name] then -- Only if the limit exists
          increments[strip(increment_parts[1])] = tonumber(strip(increment_parts[2]))
        end
      end
    end
  end

  return increments
end


local _M = {}


function _M.execute(conf)
  kong.ctx.plugin.increments = {}

  if not next(conf.limits) then
    return
  end

  -- Parse header
  local increments = parse_header(kong.service.response.get_header(conf.header_name), conf.limits)

  kong.ctx.plugin.increments = increments

  local usage = kong.ctx.plugin.usage -- Load current usage
  if not usage then
    return
  end

  local stop
  local ngx_ctx = ngx.ctx
  for limit_name in pairs(usage) do
    for period_name, lv in pairs(usage[limit_name]) do
      if not conf.hide_client_headers then
        local remain = math_max(0, lv.remaining - (increments[limit_name] and increments[limit_name] or 0))
        pdk_rl_set_limit_by_with_identifier(ngx_ctx, period_name, lv.limit, remain, nil, limit_name)
      end

      if increments[limit_name] and increments[limit_name] > 0 and lv.remaining <= 0 then
        stop = true -- No more
      end
    end
  end

  -- Set rate-limiting response headers
  pdk_rl_set_response_headers(ngx_ctx)

  kong.response.clear_header(conf.header_name)

  -- If limit is exceeded, terminate the request
  if stop then
    kong.ctx.plugin.stop_log = true
    return kong.response.exit(429) -- Don't set a body
  end
end


return _M
