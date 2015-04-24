local constants = require "kong.constants"
local IO = require "kong.tools.io"

local _M = {}

function _M.log(args)
  if not args then args = {} end

  -- CPU cores
  local res, code = IO.os_execute("getconf _NPROCESSORS_ONLN")
  if code == 0 then
    args["cores"] = string.gsub(res, "[%\r%\n]", "")
  end
  -- Hostname
  res, code = IO.os_execute("/bin/hostname")
  if code == 0 then
    args["hostname"] = string.gsub(res, "[%\r%\n]", "")
  end
  -- Uname
  res, code = IO.os_execute("/bin/uname -a")
  if code == 0 then
    args["uname"] = string.gsub(string.gsub(res, "[%\r%\n]", ""), ";", ",")
  else
    res, code = IO.os_execute("/usr/bin/uname -a")
    if code == 0 then
      args["uname"] = string.gsub(string.gsub(res, "[%\r%\n]", ""), ";", ",")
    end
  end

  -- Append info
  local info = ""
  for k,v in pairs(args) do
    if info ~= "" then
      info = info..";"
    end
    info = info..k.."="..tostring(v)
  end

  -- Send
  IO.os_execute("nc -w1 -u "..constants.SYSLOG.ADDRESS.." "..tostring(constants.SYSLOG.PORT).." <<< \"<14>"..info.."\"")
end

return _M