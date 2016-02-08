local inspect = require "inspect"

local uuid = require "lua_uuid"
local utils = require "kong.tools.utils"
local Object = require "classic"
local Errors = require "kong.dao.errors"

--- DAO
-- this just avoids having to deal with instanciating models

local DAO = Object:extend()

function DAO:new(db, model_mt, table)
  self.db = db
  self.model_mt = model_mt
  self.table = table
end

function DAO:insert(tbl)
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
  local model = self.model_mt(tbl)
  return self.db:find(model)
end

return DAO
