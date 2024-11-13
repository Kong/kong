local concat = table.concat

local Validators = {}

Validators.validation_errors = {
  -- types
  ARRAY       = "%s is not a array: '%s'",
  STRING      = "%s is not a string: '%s'",
  NUMBER      = "%s is not a number: '%s'",
  BOOLEAN     = "%s is not a boolean: '%s'",
  NGX_BOOLEAN = "%s is not a ngx_boolean: '%s'",
  -- validations
  BETWEEN     = "%s value should be between %d and %d, it's not '%s'",
  ENUM        = "%s has an invalid value: '%s', expected one of: %s",
  VALIDATION  = "%s failed validating: %s",
}

Validators.validators = {
  between = function(name, value, limits)
    if value < limits[1] or value > limits[2] then
      return nil, Validators.validation_errors.BETWEEN:format(name, limits[1], limits[2], value)
    end
    return true
  end,

  enum = function(name, value, options)
    for i = 1, #options do
      if value == options[i] then
        return true
      end
    end
    return nil, Validators.validation_errors.ENUM:format(name, value, concat(options, ", "))
  end
}

Validators.validators_order = {
  "between",
  "enum",
}

Validators.TYP_CHECKS = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end,
  ngx_boolean = function(v) return v == "on" or v == "off" end,
}

function Validators:check(config)
  local validators = self.validation_order

  local schema = config.schema
  local name = config.name
  local value = config.value
  local typ = schema.typ or "string"

  if not self.TYP_CHECKS[typ](value) then
    return false, self.validation_errors[typ:upper()]:format(name, value)
  end

  for i = 1, #validators do
    local k = validators[i]
    if schema[k] ~= nil then

      local ok, err = self.validators[k](name, value, schema[k])
      if not ok then
        if not err then
          err = (self.validation_errors[k:upper()]
            or self.validation_errors.VALIDATION):format(name, value)
        end
        return false, err
      end
    end
  end

  return true
end

return Validators
