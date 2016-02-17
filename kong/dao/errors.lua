local constants = require "kong.constants"
local printable_mt = require "kong.tools.printable"
local setmetatable = setmetatable
local getmetatable = getmetatable
local tostring = tostring
local type = type

local error_mt = {}
--error_mt.__index = error_mt

function error_mt:__tostring()
  return tostring(self.message)
end

function error_mt.__concat(a, b)
  if getmetatable(a) == error_mt then
    return tostring(a)..b
  else
    return a..tostring(b)
  end
end

local ERRORS = {
  [constants.DB_ERROR_TYPES.UNIQUE] = function(tbl)
    local ret = {}
    for k, v in pairs(tbl) do
      ret[k] = "already exists with value '"..v.."'"
    end
    return ret
  end,
  [constants.DB_ERROR_TYPES.FOREIGN] = function(tbl)
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
      return nil
    elseif getmetatable(err) == error_mt then
      return err
    end

    local err_tbl

    if type(err) == "table" then
      if ERRORS[err_type] ~= nil then
        err_tbl = ERRORS[err_type](err)
        setmetatable(err_tbl, printable_mt)
        err = tostring(err_tbl)
      else
        err_tbl = err
        setmetatable(err, printable_mt)
        err = tostring(err)
      end
    end

    local err_obj = {
      message = err,
      err_tbl = err_tbl,
      [err_type] = true
    }

    return setmetatable(err_obj, error_mt)
  end
end

local Errors = {}

for _, v in pairs(constants.DB_ERROR_TYPES) do
  Errors[v] = build_error(v)
end

return Errors
