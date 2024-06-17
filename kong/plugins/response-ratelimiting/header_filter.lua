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
local pdk_rl_store_response_header = pdk_private_rl.store_response_header
local pdk_rl_apply_response_headers = pdk_private_rl.apply_response_headers


local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"


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
        local limit_hdr  = RATELIMIT_LIMIT .. "-" .. limit_name .. "-" .. period_name
        local remain_hdr = RATELIMIT_REMAINING .. "-" .. limit_name .. "-" .. period_name
        local remain = math_max(0, lv.remaining - (increments[limit_name] and increments[limit_name] or 0))

        pdk_rl_store_response_header(ngx_ctx, limit_hdr, lv.limit)
        pdk_rl_store_response_header(ngx_ctx, remain_hdr, remain)
      end

      if increments[limit_name] and increments[limit_name] > 0 and lv.remaining <= 0 then
        stop = true -- No more
      end
    end
  end

  pdk_rl_apply_response_headers(ngx_ctx)

  kong.response.clear_header(conf.header_name)

  -- If limit is exceeded, terminate the request
  if stop then
    kong.ctx.plugin.stop_log = true
    return kong.response.exit(429) -- Don't set a body
  end
end


return _M
