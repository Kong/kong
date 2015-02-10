-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
local ltn12 = require "ltn12"
local yaml = require "yaml"
local http = require "socket.http"
local url = require "socket.url"
local lfs = require "lfs"

local _M = {}

--
-- General utils
--
function _M.table_size(t)
  local res = 0
  for _,_ in pairs(t) do
    res = res + 1
  end
  return res
end

function _M.reverse_table(arr)
  local reversed = {}
  for _, i in ipairs(arr) do
    table.insert(reversed, 1, i)
  end
  return reversed
end

-- Add an error message to a key/value table
-- Can accept a nil argument, and if is nil, will initialize the table
--
-- @param {table|nil} errors Table to attach the error to
-- @param {string} k Key of the error
-- @param v Value of the error
-- @return {table} errors
function _M.add_error(errors, k, v)
  if not errors then errors = {} end

  if errors and errors[k] then
    local list = {}
    table.insert(list, errors[k])
    table.insert(list, v)
    errors[k] = list
  else
    errors[k] = v
  end

  return errors
end

--
-- DAO utils
--
function _M.load_configuration_and_dao(configuration_path)
  local configuration_file = _M.read_file(configuration_path)
  if not configuration_file then
    error("No configuration file at: "..configuration_path)
  end
  local configuration = yaml.load(configuration_file)

  local dao_config = configuration.databases_available[configuration.database]
  if dao_config == nil then
    error("No dao \""..configuration.database.."\" defined")
  end

  local dao_factory = require("kong.dao."..configuration.database..".factory")
  local dao = dao_factory(dao_config.properties)

  return configuration, dao
end

--
-- Date utils
--

-- Returns a UNIX timestamp formatted in Coordinated Universal Time
-- If ngx is available, will use ngx.now() stripping out the milliseconds
-- Otherwise, will use os.time
-- @return {number} Current UTC timestamp
function _M.get_utc()
  if ngx then
    return math.floor(ngx.now())
  else
    return os.time(os.date("!*t"))
  end
end

--[[
local epoch = { year = 1970, month = 1, day = 1, hour = 0, min = 0, sec = 0, isdst = false }
local function gmtime(t)
  t.isdst =  false
  return os.time(t) - os.time(epoch)
end

function _M.get_timestamps(now)
  -- Convert milliseconds to seconds. Milliseconds in openresty are in decimal places
  local _now = math.floor(now)
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

  return {
          second = second * 1000,
          minute = minute * 1000,
          hour = hour * 1000,
          day = day * 1000,
          month = month * 1000,
          year = year * 100
        }
end
--]]

--
-- Lapis utils
--
function _M.show_response(status, message)
  ngx.header["X-Kong-Version"] = configuration.version
  ngx.status = status

  if (type(message) == "table") then
    ngx.print(cjson.encode(message))
  else
    ngx.print(cjson.encode({ message = message }))
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

function _M.no_content(message)
  _M.show_response(204, message)
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

--
-- Disk I/O utils
--
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

function _M.retrieve_files(path, pattern)
  if not pattern then pattern = "" end
  local files = {}

  for file in lfs.dir(path) do
    if file ~= "." and file ~= ".." and string.match(file, pattern) ~= nil then
      local f = path..'/'..file
      local attr = lfs.attributes(f)
      if attr.mode == "file" then
        table.insert(files, f)
      end
    end
  end

  return files
end

--
-- Lua scripts utils
--

-- getopt, POSIX style command line argument parser
-- param arg contains the command line arguments in a standard table.
-- param options is a string with the letters that expect string values.
-- returns a table where associated keys are true, nil, or a string value.
-- The following example styles are supported
--   -a one  ==> opts["a"]=="one"
--   -bone   ==> opts["b"]=="one"
--   -c      ==> opts["c"]==true
--   --c=one ==> opts["c"]=="one"
--   -cdaone ==> opts["c"]==true opts["d"]==true opts["a"]=="one"
-- note POSIX demands the parser ends at the first non option
--      this behavior isn't implemented.
function _M.getopt( arg, options )
  local tab = {}
  for k, v in ipairs(arg) do
    if string.sub( v, 1, 2) == "--" then
      local x = string.find( v, "=", 1, true )
      if x then tab[ string.sub( v, 3, x-1 ) ] = string.sub( v, x+1 )
      else tab[ string.sub( v, 3 ) ] = true end
    elseif string.sub( v, 1, 1 ) == "-" then
      local y = 2
      local l = string.len(v)
      local jopt
      while ( y <= l ) do
        jopt = string.sub( v, y, y )
        if string.find( options, jopt, 1, true ) then
          if y < l then
            tab[ jopt ] = string.sub( v, y+1 )
            y = l
          else
            tab[ jopt ] = arg[ k + 1 ]
          end
        else
          tab[ jopt ] = true
        end
        y = y + 1
      end
    end
  end
  return tab
end

--
-- HTTP calls utils
--

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
function _M.build_query(tab, key)
  if ngx then
    return ngx.encode_args(tab)
  else
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
        query[#query+1] = _M.build_query(value, name)
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
end

local function http_call(options)
  -- Set Host header accordingly
  if not options.headers["host"] then
    local parsed_url = url.parse(options.url)
    local port_segment = ""
    if parsed_url.port then
      port_segment = ":" .. parsed_url.port
    end
    options.headers["host"] = parsed_url.host .. port_segment
  end

  -- Returns: response, code, headers
  local resp = {}
  options.sink = ltn12.sink.table(resp)

  local r, code, headers = http.request(options)
  return resp[1], code, headers
end

-- GET methpd
function _M.get(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, _M.build_query(querystring))
  end

  return http_call {
    method = "GET",
    url = url,
    headers = headers
  }
end

-- POST methpd
function _M.post(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local body = _M.build_query(form)
  headers["content-length"] = string.len(body)
  headers["content-type"] = "application/x-www-form-urlencoded"

  return http_call {
    method = "POST",
    url = url,
    headers = headers,
    source = ltn12.source.string(body)
  }
end

-- DELETE methpd
function _M.delete(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, _M.build_query(querystring))
  end

  return http_call {
    method = "DELETE",
    url = url,
    headers = headers
  }
end

--
-- Printable
--
local colors = {
  -- attributes
  reset = 0,
  clear = 0,
  bright = 1,
  dim = 2,
  underscore = 4,
  blink = 5,
  reverse = 7,
  hidden = 8,
  -- foreground
  black = 30,
  red = 31,
  green = 32,
  yellow = 33,
  blue = 34,
  magenta = 35,
  cyan = 36,
  white = 37,
  -- background
  onblack = 40,
  onred = 41,
  ongreen = 42,
  onyellow = 43,
  onblue = 44,
  onmagenta = 45,
  oncyan = 46,
  onwhite = 47
}

local colormt = {}
colormt.__metatable = {}

function colormt:__tostring()
  return self.value
end

function colormt:__concat(other)
  return tostring(self) .. tostring(other)
end

function colormt:__call(s)
  return self .. s .. _M.reset
end

local function makecolor(value)
  return setmetatable({ value = string.char(27) .. '[' .. tostring(value) .. 'm' }, colormt)
end

for c, v in pairs(colors) do
  _M[c] = makecolor(v)
end

return _M
