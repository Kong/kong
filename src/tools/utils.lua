local constants = require "kong.constants"
local cjson = require "cjson"
local yaml = require "yaml"

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

function _M.deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[_M.deepcopy(orig_key)] = _M.deepcopy(orig_value)
    end
    setmetatable(copy, _M.deepcopy(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

_M.sort = {
  descending = function(a, b) return a > b end,
  ascending = function(a, b) return a < b end
}

function _M.sort_table_iter(t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0
  local iter = function ()
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
-- Disk I/O
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

function _M.file_exists(name)
   local f = io.open(name, "r")
   if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
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

  -- Configuraiton should already be validated by the CLI at this point
  local DaoFactory = require("kong.dao."..configuration.database..".factory")
  local dao_factory = DaoFactory(dao_config.properties)

  return configuration, dao_factory
end

--
-- Response utils
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

function _M.unsupported_media_type(required_type)
  _M.show_response(415, "Unsupported Content-Type. Use \""..required_type.."\"")
end

function _M.created(message)
  _M.show_response(201, message)
end

function _M.not_found(message)
  message = message and message or "Not found"
  _M.show_error(404, message)
end

return _M
