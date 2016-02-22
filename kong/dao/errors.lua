local printable_mt = require "kong.tools.printable"
local setmetatable = setmetatable
local getmetatable = getmetatable
local tostring = tostring
local type = type

local error_mt = {}

function error_mt.__tostring(t)
  return tostring(t.message)
end

function error_mt.__concat(a, b)
  if getmetatable(a) == error_mt then
    return tostring(a)..b
  else
    return a..tostring(b)
  end
end

local ERRORS = {
  unique = "unique",
  foreign = "foreign",
  schema = "schema",
  db = "db"
}

local serializers = {
  [ERRORS.unique] = function(tbl)
    local ret = {}
    for k, v in pairs(tbl) do
      ret[k] = "already exists with value '"..v.."'"
    end
    return ret
  end,
  [ERRORS.foreign] = function(tbl)
    local ret = {}
    for k, v in pairs(tbl) do
      ret[k] = "does not exist with value '"..v.."'"
    end
    return ret
  end
}

local function build_error(err_type)
  return function(err)
    if err == nil then
      return
    elseif getmetatable(err) == error_mt then
      return err
    end

    local err_obj = {
      [err_type] = true
    }

    if type(err) == "table" then
      if serializers[err_type] ~= nil then
        err_obj.tbl = serializers[err_type](err)
      else
        err_obj.tbl = err
      end
    end

    if err_obj.tbl then
      setmetatable(err_obj.tbl, printable_mt)
      err_obj.message = tostring(err_obj.tbl)
    else
      err_obj.message = err
    end

    return setmetatable(err_obj, error_mt)
  end
end

local _M = {}

for _, v in pairs(ERRORS) do
  _M[v] = build_error(v)
end

return _M
