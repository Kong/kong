local constants = require "kong.constants"
local printable_mt = require "kong.tools.printable"
local setmetatable = setmetatable
local getmetatable = getmetatable
local tostring = tostring
local type = type

local error_mt = {}
error_mt.__index = error_mt

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

local function build_error(err_type)
  return function(err)
    local err_tbl -- in case arg1 is a table

    if err == nil then
      return nil
    elseif getmetatable(err) == error_mt then
      return err
    elseif type(err) == "table" then
      err_tbl = err
      setmetatable(err, printable_mt)
      err = tostring(err) -- convert to string
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
