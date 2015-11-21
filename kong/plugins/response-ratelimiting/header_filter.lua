local stringy = require "stringy"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

local _M = {}

local function parse_header(header_value, limits)
  local increments = {}
  if header_value then
    local parts = stringy.split(header_value, ",")
    for _, v in ipairs(parts) do
      local increment_parts = stringy.split(v, "=")
      if utils.table_size(increment_parts) == 2 then
        local limit_name = stringy.strip(increment_parts[1])
        if limits[limit_name] then -- Only if the limit exists
          increments[stringy.strip(increment_parts[1])] = tonumber(stringy.strip(increment_parts[2]))
        end
      end
    end
  end
  return increments
end

function _M.execute(conf)
  if utils.table_size(conf.limits) <= 0 then
    return
  end

  -- Parse header
  local increments = parse_header(ngx.header[conf.header_name], conf.limits)
  ngx.ctx.increments = increments

  local usage = ngx.ctx.usage -- Load current usage

  -- Set headers describing the relevant limits to API users
  for limit_name, v in pairs(usage) do
    for period_name, lv in pairs(usage[limit_name]) do
      ngx.header[constants.HEADERS.RATELIMIT_LIMIT.."-"..limit_name.."-"..period_name] = lv.limit
      ngx.header[constants.HEADERS.RATELIMIT_REMAINING.."-"..limit_name.."-"..period_name] = math.max(0, lv.remaining - (increments[limit_name] and increments[limit_name] or 0)) -- increment_value for this current request
    end
  end

  -- Remove header
  ngx.header[conf.header_name] = nil

end

return _M
