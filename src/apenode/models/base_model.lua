-- Copyright (C) Mashape, Inc.

local rex = require("rex_pcre")

local BaseModel = {}
BaseModel.__index = BaseModel

setmetatable(BaseModel, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

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

function BaseModel:_validate(t, schema, is_update)
  local result = {}
  local errors

  for k,v in pairs(schema) do
    if not t[k] and v.default ~= nil then
      t[k] = v.default
    elseif not t[k] and v.required then
      errors = add_error(errors, k, k .. " is required")
    elseif t[k] and not is_update and v.read_only then
      errors = add_error(errors, k, k .. " is read only")
    end

    if t[k] and type(t[k]) ~= v.type then
      errors = add_error(errors, k, k .. " should be a " .. v.type)
    end

    if t[k] and v.unique then
      local data, total, err = self._find(self._collection, {[k] = t[k]})
      if total > 0 then
        errors = add_error(errors, k, k .. " with value " .. "\"" .. t[k] .. "\"" .. " already exists")
      end
    end

    if t[k] and v.regex then
      if not rex.match(t[k], v.regex) then
        errors = add_error(errors, k, k .. " has an invalid value")
      end
    end

    if t[k] and v.func then
      local success, err = v.func(t[k])
      if not success then
        errors = add_error(errors, k, err)
      end
    end

    result[k] = t[k]
    self[k] = t[k]
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

---------------
-- BaseModel --
---------------

function BaseModel:_init(collection, t, schema)
  -- The collection needs to be declared before just in case
  -- the validator needs it for the "unique" check
  self._collection = collection

  -- Validate the entity
  if not t then t = {} end
  local result, errors = self:_validate(t, schema)
  if errors then
    return nil, errors
  end

  self._t = result
  return self
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
  local res, err = validate(self, self._t, self._SCHEMA, true)
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
