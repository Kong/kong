local inspect = require "inspect"

local uuid = require "lua_uuid"
local utils = require "kong.tools.utils"
local Object = require "classic"
local Errors = require "kong.dao.errors"

local function check_arg(arg, arg_n, exp_type)
  if type(arg) ~= exp_type then
    local info = debug.getinfo(2)
    local err = string.format("bad argument #%d to '%s' (%s expected, got %s)",
                              arg_n, info.name, exp_type, type(arg))
    error(err, 3)
  end
end

local function check_not_empty(tbl, arg_n)
  if next(tbl) == nil then
    local info = debug.getinfo(2)
    local err = string.format("bad argument #%d to '%s' (expected table to not be empty)",
                              arg_n, info.name)
    error(err, 3)
  end
end

local function check_subset_of_schema(tbl, arg_n, fields)
  for col in pairs(tbl) do
    if fields[col] == nil then
      local info = debug.getinfo(2)
      local err = string.format("bad argument #%d to '%s' (field '%s' not in schema)",
                                arg_n, info.name, col)
      error(err, 3)
    end
  end
end

--- DAO
-- this just avoids having to deal with instanciating models

local DAO = Object:extend()

function DAO:new(db, model_mt, schema)
  self.db = db
  self.model_mt = model_mt
  self.schema = schema
  self.table = schema.table
end

function DAO:insert(tbl)
  check_arg(tbl, 1, "table")

  local model = self.model_mt(tbl)
  local ok, err = model:validate()
  if not ok then
    return nil, err
  end

  for col, field in pairs(model.__schema.fields) do
    if field.dao_insert_value and model[col] == nil then
      local f = self.db.dao_insert_values[field.type]
      if f then
        model[col] = f()
      end
    end
  end

  return self.db:insert(model)
end

function DAO:find(tbl)
  check_arg(tbl, 1, "table")

  local model = self.model_mt(tbl)
  return self.db:find(model)
end

function DAO:find_all(tbl)
  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    check_subset_of_schema(tbl, 1, self.schema.fields)
  end

  return self.db:find_all(self.table, tbl, self.schema)
end

function DAO:count(tbl)
  if tbl ~= nil then
    check_arg(tbl, 1, "table")
    check_not_empty(tbl, 1)
    check_subset_of_schema(tbl, 1, self.schema.fields)
  end

  return self.db:count(self.table, tbl, self.schema)
end

return DAO
