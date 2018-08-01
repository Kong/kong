local Schema = require("kong.db.schema")

local Entity = {}


local entity_errors = {
  NO_NILABLE = "%s: Entities cannot have nilable types.",
  MAP_KEY_STRINGS_ONLY = "%s: Map keys must be strings",
  AGGREGATE_ON_BASE_TYPES_ONLY = "%s: Aggregates are allowed on base types only."
}


local base_types = {
  string = true,
  number = true,
  boolean = true,
  integer = true,
}


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
      if not base_types[field.values.type] then
        return nil, entity_errors.AGGREGATE_ON_BASE_TYPES_ONLY:format(name)
      end

    elseif field.type == "array" or field.type == "set" then
      if not base_types[field.elements.type] then
        return nil, entity_errors.AGGREGATE_ON_BASE_TYPES_ONLY:format(name)
      end

    end

    ::continue::
  end

  return self
end


return Entity
