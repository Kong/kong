-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"

local _M = {}

function _M.table_size(t)
  local res = 0
  for _,_ in pairs(t) do
    res = res + 1
  end
  return res
end

function _M.show_response(status, message)
  ngx.header["X-Apenode-Version"] = configuration.version
  ngx.status = status
  if (type(message) == "table") then
    ngx.print(cjson.encode(message))
  else
    ngx.print(cjson.encode({message = message}))
  end
  ngx.exit(status)
end

function _M.show_error(status, message)
  ngx.ctx.error = true
  _M.show_response(status, message)
end

function _M.success(message)
  _M.show_response(200, message)
end

function _M.created(message)
  _M.show_response(201, message)
end

function _M.not_found(message)
  message = message or "Not found"
  _M.show_error(404, message)
end

function _M.create_timer(func, data)
  local ok, err = ngx.timer.at(0, func, data)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
    return
  end
end

function _M.read_file(path)
  local contents = nil
  local file = io.open(path, "rb")
  if file then
    contents = file:read("*all")
    file:close()
  end
  return contents
end

function _M.write_to_file(path, value)
  local file = io.open(path, "w")
  file:write(value)
  file:close()
end

local epoch = {year=1970, month=1, day=1, hour=0, min=0, sec=0, isdst=false }
local function gmtime(t)
   t.isdst =  false
   return os.time(t) - os.time(epoch)
end

function _M.get_timestamps(now)
  local _now = math.floor(now) -- Convert milliseconds to seconds. Milliseconds in openresty are in decimal places
  local date = os.date("!*t", _now) -- In milliseconds

  local second = _now
  date.sec = 0
  local minute = gmtime(date)
  date.min = 0
  local hour = gmtime(date)
  date.hour = 0
  local day = gmtime(date)
  date.day = 1
  local month = gmtime(date)
  date.month = 1
  local year = gmtime(date)

  return {second=second * 1000, minute=minute * 1000, hour=hour * 1000,day=day * 1000, month=month * 1000, year=year * 1000}
end

return _M
