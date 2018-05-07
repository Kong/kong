local Schema = require("kong.db.schema")

local Entity = {}


local entity_errors = {
  NO_NILABLE = "Entities cannot have nilable types.",
  MAP_KEY_STRINGS_ONLY = "Map keys must be strings",
  AGGREGATE_ON_BASE_TYPES_ONLY = "Aggregates are allowed on base types only."
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
      return nil, entity_errors.NO_NILABLE
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

    elseif field.type == "record" then
      for _, entry in ipairs(field.fields) do
        if not base_types[entry[next(entry)].type] then
          return nil, entity_errors.AGGREGATE_ON_BASE_TYPES_ONLY:format(name)
        end
      end
    end
  end

  return self
end


return Entity
