local constants = require "kong.constants"
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

function _M.is_empty(t)
  return next(t) == nil
end

_M.sort = {
  descending = function(a, b) return a > b end,
  ascending = function(a, b) return a < b end
}

function _M.sort_table(t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

function _M.reverse_table(arr)
  -- this could be O(n/2)
  local reversed = {}
  for _, i in ipairs(arr) do
    table.insert(reversed, 1, i)
  end
  return reversed
end

function _M.array_contains(arr, val)
  for _,v in pairs(arr) do
    if v == val then
      return true
    end
  end
  return false
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
-- Scripts utils
--
local logger = {}
local logger_mt = {__index=logger}

function logger:new(silent)
  return setmetatable({ silent = silent }, logger_mt)
end

function logger:log(str)
  if not self.silent then
    print(str)
  end
end

function logger:success(str)
  self:log(_M.green("✔  ")..str)
end

function logger:error(str)
  self:log(_M.red("✘  ")..str)
  os.exit(1)
end

_M.logger = logger

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
-- Lapis utils
--
function _M.show_response(status, message, raw)
  ngx.header[constants.HEADERS.SERVER] = "kong/"..constants.VERSION
  ngx.status = status

  if raw then
    ngx.print(message)
  elseif (type(message) == "table") then
    ngx.print(cjson.encode(message))
  else
    ngx.print(cjson.encode({ message = message }))
  end

  ngx.exit(status)
end

function _M.show_error(status, message)
  ngx.ctx.error = true
  if not message then
    message = "An error occurred"
  end
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
-- Cache utils
--
function _M.cache_set(key, value, exptime)
  if exptime == nil then exptime = 0 end -- By default never expire
  local cache = ngx.shared.cache
  if value then
    value = cjson.encode(value)
  end
  if ngx then
    ngx.log(ngx.DEBUG, " saving cache key \""..key.."\": "..value)
  end
  local succ, err, forcible = cache:set(key, value, exptime)
  return succ, err, forcible
end

function _M.cache_get(key)
  if ngx then
    ngx.log(ngx.DEBUG, " Try to get cache key \""..key.."\"")
  end

  local cache = ngx.shared.cache
  local value, flags = cache:get(key)
  if value then
    if ngx then
      ngx.log(ngx.DEBUG, " Found cache value for key \""..key.."\": "..value)
    end
    value = cjson.decode(value)
  end
  return value, flags
end

function _M.cache_delete(key)
  local cache = ngx.shared.cache
  cache:delete(key)
end

function _M.cache_api_key(host)
  return constants.CACHE.APIS.."/"..host
end

function _M.cache_plugin_key(name, api_id, application_id)
  return constants.CACHE.PLUGINS.."/"..name.."/"..api_id..(application_id and "/"..application_id or "")
end

function _M.cache_application_key(public_key)
  return constants.CACHE.APPLICATIONS.."/"..public_key
end

function _M.cache_get_and_set(key, cb)
  local val = _M.cache_get(key)
  if not val then
    val = cb()
    if val then
      local succ, err = _M.cache_set(key, val)
      if not succ and ngx then
        ngx.log(ngx.ERR, err)
      end
    end
  end
  return val
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
        table.insert(files, { file = f, name = file })
      end
    end
  end

  return files
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
        value = tostring(value)
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

  local _, code, headers = http.request(options)
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

-- PUT method
function _M.put(url, table, headers)
  if not headers then headers = {} end
  if not table then table = {} end
  local raw_json = cjson.encode(table)

  headers["content-length"] = string.len(raw_json)
  headers["content-type"] = "application/json"

  return http_call {
    method = "PUT",
    url = url,
    headers = headers,
    source = ltn12.source.string(raw_json)
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
