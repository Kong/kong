-- Copyright (C) Mashape, Inc.

local BaseModel = {}
BaseModel.__index = BaseModel

setmetatable(BaseModel, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

local function add_error(errors, k, v)
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

local function validate(object, t, schema, is_update)
  local errors = {}

  for k,v in pairs(schema) do
    if v.required and not t[k] then
      if v.default then
        t[k] = v.default
      else
        errors = add_error(errors, k, k .. " is required")
      end
    end
    if not is_update and v.read_only and t[k] then
      errors = add_error(errors, k, k .. " is read only")
    end
    if t[k] and type(t[k]) ~= v.type then
      errors = add_error(errors, k, k .. " should be a " .. v.type)
    end

    object[k] = t[k]
  end

  if errors then
    return false, errors
  end

  return true
end

function BaseModel:_init(collection, t, schema)
  if not t then t = {} end

  validate(self, t, schema)

  self._t = t
  self._schema = schema
  self._collection = collection
end

function BaseModel:save()
  local data, err = dao[self._collection]:save(self._t)
  return data, err
end

function BaseModel:delete()
  local n_success, err = BaseModel:find_and_delete({id = self._t.id})
  return n_success, err
end

function BaseModel:update()
  local res, err = validate(self, self._t, self._schema, true)
  if not res then
    return nil, err
  else
    local data, err = dao[self._collection]:update(self._t)
    return data, err
  end
end

function BaseModel.find(args, page, size)
  local data, total, err = dao[self._collection]:find(args, page, size)
  return data, total, err
end

function BaseModel.find_and_delete(args)
  local n_success, err = dao[self._collection]:delete(args)
  return n_success, err
end

return BaseModel
