local Schema = require("kong.db.schema")

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


function Entity.new_subschema(schema, key, definition)
  make_records_required(definition)
  definition.required = nil
  return Schema.new_subschema(schema, key, definition)
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

    if field.abstract then
      goto continue
    end

    if field.type == "map" then
      if field.keys.type ~= "string" then
        return nil, entity_errors.MAP_KEY_STRINGS_ONLY:format(name)
      end

    elseif field.type == "record" then
      make_records_required(field)

    elseif field.type == "function" then
      return nil, entity_errors.NO_FUNCTIONS:format(name)
    end

    ::continue::
  end

  self.new_subschema = Entity.new_subschema

  return self
end


return Entity
