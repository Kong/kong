-- Copyright (C) Mashape, Inc.

local http = require "socket.http"
local url = require "socket.url"
local cjson = require "cjson"

local _M = {}

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
local function build_query(tab, key)
  local query = {}
  local keys = {}

  for k in pairs(tab) do
    keys[#keys+1] = k
  end

  table.sort(keys)

  for _,name in ipairs(keys) do
    local value = tab[name]
    if key then
      name = string.format("%s[%s]", tostring(key), tostring(name))
    end
    if type(value) == "table" then
      query[#query+1] = build_query(value, name)
    else
      local value = tostring(value)
      if value ~= "" then
        query[#query+1] = string.format("%s=%s", name, value)
      else
        query[#query+1] = name
      end
    end
  end

  return table.concat(query, "&")
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

function _M.http_call(method, url, querystring, body, cb)
  local bodyStr

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end
  if body then
    bodyStr = build_query(body)
  end

  local body, res_code, res_headers, res_status = http.request(url, bodyStr)

  if cb then
    cb(res_code, body, res_headers)
  end
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

function _M.get(url, querystring, cb)
  if type(querystring) == "function" then
    cb = querystring
    querystring = nil
  end
  _M.http_call("GET", url, querystring, nil, cb)
end

function _M.post(url, form, cb)
  if type(form) == "function" then
    cb = form
    form = nil
  end
  _M.http_call("POST", url, nil, form, cb)
end

return _M
