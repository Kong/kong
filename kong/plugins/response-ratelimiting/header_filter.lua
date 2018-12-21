local utils = require "kong.tools.utils"


local kong = kong
local next = next
local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local math_max = math.max


local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"


local function parse_header(header_value, limits)
  local increments = {}

  if header_value then
    local parts
    if type(header_value) == "table" then
      parts = header_value
    else
      parts = utils.split(header_value, ",")
    end

    for _, v in ipairs(parts) do
      local increment_parts = utils.split(v, "=")
      if #increment_parts == 2 then
        local limit_name = utils.strip(increment_parts[1])
        if limits[limit_name] then -- Only if the limit exists
          increments[utils.strip(increment_parts[1])] = tonumber(utils.strip(increment_parts[2]))
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
  for limit_name in pairs(usage) do
    for period_name, lv in pairs(usage[limit_name]) do
      if not conf.hide_client_headers then
        -- increment_value for this current request
        local limit_hdr  = RATELIMIT_LIMIT .. "-" .. limit_name .. "-" .. period_name
        local remain_hdr = RATELIMIT_REMAINING .. "-" .. limit_name .. "-" .. period_name
        kong.response.set_header(limit_hdr, lv.limit)

        local remain = math_max(0, lv.remaining - (increments[limit_name] and increments[limit_name] or 0))
        kong.response.set_header(remain_hdr, remain)
      end

      if increments[limit_name] and increments[limit_name] > 0 and lv.remaining <= 0 then
        stop = true -- No more
      end
    end
  end

  kong.response.clear_header(conf.header_name)

  -- If limit is exceeded, terminate the request
  if stop then
    kong.ctx.plugin.stop_log = true
    return kong.response.exit(429) -- Don't set a body
  end
end


return _M
