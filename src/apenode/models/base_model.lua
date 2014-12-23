-- Copyright (C) Mashape, Inc.

local rex = require("rex_pcre")
local stringy = require "stringy"

local Object = require "classic"
local BaseModel = Object:extend()

-------------
-- PRIVATE --
-------------

local function add_error(errors, k, v)
  if not errors then errors = {} end

  if errors[k] then
    local list = {}
    table.insert(list, errors[k])
    table.insert(list, v)
    errors[k] = list
  else
    errors[k] = v
  end
  return errors
end
---------------
-- BaseModel --
---------------

function BaseModel:new(collection, schema, t)
  -- The collection needs to be declared before just in case
  -- the validator needs it for the "unique" check
  self._collection = collection

  -- Validate the entity
  if not t then t = {} end
  local result, errors = self:_validate(schema, t)
  if errors then
    return nil, errors
  end

  for k,v in pairs(t) do
    self[k] = t[k]
  end

  self._t = result
end

function BaseModel:_validate(schema, t, is_update)
  local result = {}
  local errors

  for k,v in pairs(schema) do
    if not t[k] and v.default ~= nil then
      t[k] = v.default
    elseif v.required and (t[k] == nil or t[k] == "") then
      errors = add_error(errors, k, k .. " is required")
    elseif t[k] and not is_update and v.read_only then
      errors = add_error(errors, k, k .. " is read only")
    end

    if t[k] and type(t[k]) ~= v.type then
      errors = add_error(errors, k, k .. " should be a " .. v.type)
    end

    if t[k] and v.regex then
      if not rex.match(t[k], v.regex) then
        errors = add_error(errors, k, k .. " has an invalid value")
      end
    end

    if v.func then
      local success, err = v.func(t[k], t)
      if not success then
        errors = add_error(errors, k, err)
      end
    end

    if t[k] and v.unique then
      local data, total, err = self._find(self._collection, {[k] = t[k]})
      if total > 0 then
        errors = add_error(errors, k, k .. " with value " .. "\"" .. t[k] .. "\"" .. " already exists")
      end
    end

    if t[k] and v.type == "table" then
      if v.schema_from_func then
        local table_schema, err = v.schema_from_func(t)
        if not table_schema then
          errors = add_error(errors, k, err)
        else
          local _, table_schema_err = BaseModel:_validate(table_schema, t[k], false)
          if table_schema_err then
            errors = add_error(errors, k, table_schema_err)
          end
        end
      end
    end

    result[k] = t[k]
  end

  -- Check for unexpected fields
  for k,v in pairs(t) do
    if not schema[k] then
      errors = add_error(errors, k, k .. " is an unknown field")
    end
  end

  if errors then
    result = nil
  end

  return result, errors
end


function BaseModel:save()
  local data, err = dao[self._collection]:insert_or_update(self._t)
  return data, err
end

function BaseModel:delete()
  local n_success, err = BaseModel:find_and_delete { id = self._t.id }
  return n_success, err
end

function BaseModel:update()
  local res, err = self:_validate(self._SCHEMA, self._t, true)
  if not res then
    return nil, err
  else
    local data, err = dao[self._collection]:update(self._t)
    return data, err
  end
end

function BaseModel._find_one(collection, args)
  local data, err = dao[collection]:find_one(args)
  return data, err
end

function BaseModel._find(collection, args, page, size)
  local data, total, err = dao[collection]:find(args, page, size)
  return data, total, err
end

function BaseModel._find_and_delete(collection, args)
  local n_success, err = dao[collection]:find_and_delete(args)
  return n_success, err
end

return BaseModel
