local stringy = require "stringy"

local _M = {}

function _M.get_hostname()
  local f = io.popen ("/bin/hostname")
  local hostname = f:read("*a") or ""
  f:close()
  hostname = string.gsub(hostname, "\n$", "")
  return hostname
end

function _M.parse_status(value)
  local result = {}
  local parts = stringy.split(value, "\n")
  for i, v in ipairs(parts) do
    local part = stringy.strip(v)
    if i == 1 then
      result["connections_active"] = tonumber(string.sub(part, string.find(part, "%d+")))
    elseif i == 3 then
      local counter = 1
      local stat_names = { "connections_accepted", "connections_handled", "total_requests"}
      for stat in string.gmatch(part, "%S+") do
        result[stat_names[counter]] = tonumber(stat)
        counter = counter + 1
      end
    elseif i == 4 then
      local reading, writing, waiting = string.match(part, "%a+:%s*(%d+)%s*%a+:%s*(%d+)%s*%a+:%s*(%d+)")
      result["connections_reading"] = tonumber(reading)
      result["connections_writing"] = tonumber(writing)
      result["connections_waiting"] = tonumber(waiting)
    end
  end
  return result
end

return _M