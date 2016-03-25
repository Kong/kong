local IO = require "kong.tools.io"
local meta = require "kong.meta"
local cjson = require "cjson"
local stringy = require "stringy"
local constants = require "kong.constants"

local version = meta._VERSION

local _M = {}

function _M.log(args)
  if not args then args = {} end

  -- Kong Version
  args["version"] = version

  -- CPU cores
  local res, code = IO.os_execute("getconf _NPROCESSORS_ONLN")
  if code == 0 then
    args["cores"] = res
  end
  -- Hostname
  res, code = IO.os_execute("/bin/hostname")
  if code == 0 then
    args["hostname"] = res
  end
  -- Uname
  res, code = IO.os_execute("/bin/uname -a")
  if code == 0 then
    args["uname"] = string.gsub(res, ";", ",")
  else
    res, code = IO.os_execute("/usr/bin/uname -a")
    if code == 0 then
      args["uname"] = string.gsub(res, ";", ",")
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
  IO.os_execute("nc -w1 -u "..constants.SYSLOG.ADDRESS.." "..tostring(constants.SYSLOG.PORT).." <<< \"<14>"..info.."\" &")
end

function _M.format_entity(t)
  t.created_at = nil
  for k, v in pairs(t) do
    if stringy.endswith(k, "id") then
      t[k] = nil
    end
    if type(v) == "table" then
      t[k] = cjson.encode(v)
    end
  end
  return t
end

return _M
