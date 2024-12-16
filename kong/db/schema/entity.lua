-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Schema = require("kong.db.schema")


-- EE [[
local hooks = require("kong.hooks")
local keyring = require("kong.keyring")
-- EE ]]


local Entity = {}


local entity_errors = {
  NO_NILABLE = "%s: Entities cannot have nilable types.",
  NO_FUNCTIONS = "%s: Entities cannot have function types.",
  MAP_KEY_STRINGS_ONLY = "%s: Entities map keys must be strings.",
}


-- Make records in Entities required by default,
-- so that they return their full structure on API queries.
local function make_records_required(field)
  if field.required == nil then
    field.required = true
  end
  for _, f in Schema.each_field(field) do
    if f.type == "record" then
      make_records_required(f)
    end
  end
end


-- EE [[
local find = string.find
local sub  = string.sub

--
-- Set a field from a possibly-nested table using a string key
-- such as "x.y.z", such that `set_field(t, "x.y.z", v)` is the
-- same as `t.x.y.z = v`.
local function set_field(tbl, name, value)
  local dot = find(name, ".", 1, true)
  if not dot then
    tbl[name] = value
    return
  end
  local hd, tl = sub(name, 1, dot - 1), sub(name, dot + 1)
  local subtbl = tbl[hd]
  if subtbl == nil then
    subtbl = {}
    tbl[hd] = subtbl
  end
  set_field(subtbl, tl, value)
end

local function add_encryption_transformations(self, name, field)
  self.transformations = self.transformations or {}
  if field.type == "string" then
    table.insert(self.transformations, {
      input = { name },
      on_write = function(value)
        local tbl = {}
        set_field(tbl, name, keyring.encrypt(value, name, self))
        return tbl
      end,
      on_read = function(value)
        local tbl = {}
        set_field(tbl, name, keyring.decrypt(value))
        return tbl
      end,
    })
  elseif field.type == "array" and field.elements.type == "string" then
    table.insert(self.transformations, {
      input = { name },
      on_write = function(value)
        local xs = {}
        for i, x in ipairs(value) do
          xs[i] = keyring.encrypt(x, name, self)
        end
        local tbl = {}
        set_field(tbl, name, xs)
        return tbl
      end,
      on_read = function(value)
        local xs = {}
        for i, x in ipairs(value) do
          xs[i] = keyring.decrypt(x)
        end
        local tbl = {}
        set_field(tbl, name, xs)
        return tbl
      end,
    })
  end
end
-- EE ]]


local function find_encrypted_fields(schema, definition, prefix)
  for name, field in Schema.each_field(definition) do
    if field.encrypted then
      add_encryption_transformations(schema, prefix .. name, field)
    else
      if field.type == "record" then
        find_encrypted_fields(schema, field, prefix .. name .. ".")
      end
    end
  end
end


function Entity.load_and_validate_subschema(schema, key, definition)
  make_records_required(definition)

  definition.required = nil

  local subschema, err = Schema.load_and_validate_subschema(schema, key, definition)
  if not subschema then
    return nil, err
  end

  return subschema
end


function Entity.reset_subschema(schema, key, definition, subschema)
  Schema.reset_subschema(schema, key, subschema)

  -- EE [[
  find_encrypted_fields(schema.subschemas[key], definition, "")
  -- EE ]]
end


function Entity.new_subschema(schema, key, definition)
  make_records_required(definition)

  definition.required = nil

  local ok, err = Schema.new_subschema(schema, key, definition)
  if not ok then
    return ok, err
  end

  -- EE [[
  find_encrypted_fields(schema.subschemas[key], definition, "")
  -- EE ]]

  return ok
end


function Entity.new(definition)
  local self, err = Schema.new(definition)
  if not self then
    return nil, err
  end

  for name, field in self:each_field() do
    if field.nilable then
      return nil, entity_errors.NO_NILABLE:format(name)
    end

    if not field.abstract then

      if field.type == "map" then
        if field.keys.type ~= "string" then
          return nil, entity_errors.MAP_KEY_STRINGS_ONLY:format(name)
        end

      elseif field.type == "record" then
        make_records_required(field)

      elseif field.type == "function" then
        return nil, entity_errors.NO_FUNCTIONS:format(name)
      end

      -- EE [[
      if field.encrypted then
        add_encryption_transformations(self, name, field)
      end
      -- EE ]]
    end
  end

  self.new_subschema = Entity.new_subschema
  self.unload_subschemas = Schema.unload_subschemas

  -- EE [[
  assert(hooks.run_hook("db:schema:entity:new", self, self.name))

  if self.name then
    assert(hooks.run_hook("db:schema:".. self.name .. ":new", self))
  end
  -- EE ]]

  return self
end


return Entity
