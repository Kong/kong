-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local floor       = math.floor


local _M = {}


_M.portal_plugins = {}


_M.pluralize_time = function(val, unit)
  if val ~= 1 then
    return val .. " " .. unit .. "s"
  end

  return val .. " " .. unit
end


_M.append_time = function(val, unit, ret_string, append_zero)
  if val > 0 or append_zero then
    if ret_string == "" then
      return _M.pluralize_time(val, unit)
    end

    return ret_string .. " " .. _M.pluralize_time(val, unit)
  end

  return ret_string
end


_M.humanize_timestamp = function(seconds, append_zero)
  local day = floor(seconds/86400)
  local hour = floor((seconds % 86400)/3600)
  local minute = floor((seconds % 3600)/60)
  local second = floor(seconds % 60)

  local ret_string = ""
  ret_string = _M.append_time(day, "day", ret_string, append_zero)
  ret_string = _M.append_time(hour, "hour", ret_string, append_zero)
  ret_string = _M.append_time(minute, "minute", ret_string, append_zero)
  ret_string = _M.append_time(second, "second", ret_string, append_zero)

  return ret_string
end


return _M
