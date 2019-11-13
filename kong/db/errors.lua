local pl_pretty = require("pl.pretty").write
local pl_keys = require("pl.tablex").keys


local type         = type
local null         = ngx.null
local error        = error
local upper        = string.upper
local fmt          = string.format
local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local setmetatable = setmetatable
local getmetatable = getmetatable
local concat       = table.concat
local sort         = table.sort


local sorted_keys = function(tbl)
  local keys = pl_keys(tbl)
  sort(keys)
  return keys
end


-- error codes


local ERRORS              = {
  INVALID_PRIMARY_KEY     = 1,
  SCHEMA_VIOLATION        = 2,
  PRIMARY_KEY_VIOLATION   = 3,  -- primary key already exists (HTTP 400)
  FOREIGN_KEY_VIOLATION   = 4,  -- foreign entity does not exist (HTTP 400)
  UNIQUE_VIOLATION        = 5,  -- unique key already exists (HTTP 409)
  NOT_FOUND               = 6,  -- WHERE clause leads nowhere (HTTP 404)
  INVALID_OFFSET          = 7,  -- page(size, offset) is invalid
  DATABASE_ERROR          = 8,  -- connection refused or DB error (HTTP 500)
  INVALID_SIZE            = 9,  -- page(size, offset) is invalid
  INVALID_UNIQUE          = 10, -- unique field value is invalid
  INVALID_OPTIONS         = 11, -- invalid options given
  OPERATION_UNSUPPORTED   = 12, -- operation is not supported with this strategy
  FOREIGN_KEYS_UNRESOLVED = 13, -- foreign key(s) could not be resolved
  DECLARATIVE_CONFIG      = 14, -- error parsing declarative configuration
  TRANSFORMATION_ERROR    = 15, -- error with dao transformations
  INVALID_FOREIGN_KEY     = 16,
}


-- error codes messages


local ERRORS_NAMES                 = {
  [ERRORS.INVALID_PRIMARY_KEY]     = "invalid primary key",
  [ERRORS.SCHEMA_VIOLATION]        = "schema violation",
  [ERRORS.PRIMARY_KEY_VIOLATION]   = "primary key violation",
  [ERRORS.FOREIGN_KEY_VIOLATION]   = "foreign key violation",
  [ERRORS.UNIQUE_VIOLATION]        = "unique constraint violation",
  [ERRORS.NOT_FOUND]               = "not found",
  [ERRORS.INVALID_OFFSET]          = "invalid offset",
  [ERRORS.DATABASE_ERROR]          = "database error",
  [ERRORS.INVALID_SIZE]            = "invalid size",
  [ERRORS.INVALID_UNIQUE]          = "invalid unique %s",
  [ERRORS.INVALID_OPTIONS]         = "invalid options",
  [ERRORS.OPERATION_UNSUPPORTED]   = "operation unsupported",
  [ERRORS.FOREIGN_KEYS_UNRESOLVED] = "foreign keys unresolved",
  [ERRORS.DECLARATIVE_CONFIG]      = "invalid declarative configuration",
  [ERRORS.TRANSFORMATION_ERROR]    = "transformation error",
  [ERRORS.INVALID_FOREIGN_KEY]     = "invalid foreign key",
}


-- err_t metatable definition


local _err_mt = {
  __tostring = function(err_t)
    local message = err_t.message
    if message == nil or message == null then
       message = err_t.name
    end

    if err_t.strategy then
      return fmt("[%s] %s", err_t.strategy, message)
    end

    return message
  end,

  __concat = function(a, b)
    return tostring(a) .. tostring(b)
  end,
}


-- error module


local _M = {
  codes  = ERRORS,
  names  = ERRORS_NAMES,
}


local function new_err_t(self, code, message, errors, name)
  if type(message) == "table" and getmetatable(message) == _err_mt then
    return message
  end

  if not code then
    error("missing code")
  end

  if not ERRORS_NAMES[code] then
    error("unknown error code: " .. tostring(code))
  end

  if message and type(message) ~= "string" then
    error("message must be a string or nil")
  end

  if errors and type(errors) ~= "table" then
    error("errors must be a table or nil")
  end

  local err_t = {
    code      = code,
    name      = name or ERRORS_NAMES[code],
    message   = message or null,
    strategy  = self.strategy,
  }

  if errors then
    local fields = {}

    for k, v in pairs(errors) do
      fields[k] = v
    end

    if code == ERRORS.INVALID_OPTIONS then
      err_t.options = fields
    else
      err_t.fields = fields
    end
  end

  return setmetatable(err_t, _err_mt)
end


function _M.__index(self, k)
  if ERRORS[k] then
    return ERRORS[k]
  end

  if _M[k] then
    return _M[k]
  end

  local upper_key = upper(k)
  if ERRORS[upper_key] then
    local f = function()
      return new_err_t(self, ERRORS[upper_key])
    end

    self[k] = f

    return f
  end
end


function _M.new(strategy)
  local self = {
    strategy = strategy,
  }

  return setmetatable(self, _M)
end


function _M:invalid_primary_key(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local message = fmt("invalid primary key: '%s'", pl_pretty(primary_key, ""))

  return new_err_t(self, ERRORS.INVALID_PRIMARY_KEY, message, primary_key)
end


function _M:invalid_foreign_key(foreign_key)
  if type(foreign_key) ~= "table" then
    error("foreign_key must be a table", 2)
  end

  local message = fmt("invalid foreign key: '%s'", pl_pretty(foreign_key, ""))

  return new_err_t(self, ERRORS.INVALID_FOREIGN_KEY, message, foreign_key)
end


function _M:schema_violation(errors)
  if type(errors) ~= "table" then
    error("errors must be a table", 2)
  end

  local buf = {}
  local len = 0

  if errors["@entity"] then
    for _, err in pairs(errors["@entity"]) do
      len = len + 1
      buf[len] = err
    end
  end

  for _, field_name in ipairs(sorted_keys(errors)) do
    if field_name ~= "@entity" then
      local field_errors = errors[field_name]
      if type(field_errors) == "table" then
        for _, sub_field in ipairs(sorted_keys(field_errors)) do
          len = len + 1
          local value = field_errors[sub_field]
          if type(value) == "table" then
            value = pl_pretty(value)
          end
          buf[len] = fmt("%s.%s: %s", field_name, sub_field, value)
        end

      else
        len = len + 1
        buf[len] = fmt("%s: %s", field_name, field_errors)
      end
    end
  end

  local message

  if len == 1 then
    message = fmt("schema violation (%s)", buf[1])

  else
    message = fmt("%d schema violations (%s)",
                  len, concat(buf, "; "))
  end

  return new_err_t(self, ERRORS.SCHEMA_VIOLATION, message, errors)
end


function _M:primary_key_violation(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local message = fmt("primary key violation on key '%s'",
                      pl_pretty(primary_key, ""))

  return new_err_t(self, ERRORS.PRIMARY_KEY_VIOLATION, message, primary_key)
end


function _M:foreign_key_violation_invalid_reference(foreign_key,
                                                    foreign_key_field_name,
                                                    parent_name)
  if type(foreign_key) ~= "table" then
    error("foreign_key must be a table", 2)
  end

  if type(foreign_key_field_name) ~= "string" then
    error("foreign_key_field_name must be a string", 2)
  end

  if type(parent_name) ~= "string" then
    error("parent_name must be a string", 2)
  end

  local message = fmt("the foreign key '%s' does not reference an existing '%s' entity.",
                      pl_pretty(foreign_key, ""), parent_name)

  return new_err_t(self, ERRORS.FOREIGN_KEY_VIOLATION, message, {
    [foreign_key_field_name] = foreign_key
  })
end


function _M:foreign_key_violation_restricted(parent_name, child_name)
  if type(parent_name) ~= "string" then
    error("parent_name must be a string", 2)
  end

  if type(child_name) ~= "string" then
    error("child_name must be a string", 2)
  end

  local message = fmt("an existing '%s' entity references this '%s' entity",
                      child_name, parent_name)

  return new_err_t(self, ERRORS.FOREIGN_KEY_VIOLATION, message, {
    ["@referenced_by"] = child_name
  })
end


function _M:foreign_keys_unresolved(errors)
  if type(errors) ~= "table" then
    error("errors must be a table", 2)
  end

  local buf = {}
  local len = 0

  for _, field_name in ipairs(sorted_keys(errors)) do
    local field_errors = errors[field_name]
    if type(field_errors) == "table" then
      for _, sub_field in ipairs(sorted_keys(field_errors)) do
        len = len + 1
        local value = field_errors[sub_field]
        if type(value) == "table" then
          value = fmt("the foreign key cannot be resolved with '%s' for an existing '%s' entity",
                      pl_pretty({ [value.name] = value.value }, ""), value.parent)
        end
        field_errors[sub_field] = value
        buf[len] = fmt("%s.%s: %s", field_name, sub_field, value)
      end

    else
      len = len + 1
      buf[len] = fmt("%s: %s", field_name, field_errors)
    end
  end

  local message

  if len == 1 then
    message = fmt("foreign key unresolved (%s)", buf[1])

  else
    message = fmt("%d foreign keys unresolved (%s)",
      len, concat(buf, "; "))
  end

  return new_err_t(self, ERRORS.FOREIGN_KEYS_UNRESOLVED, message, errors)
end


function _M:unique_violation(unique_key)
  if type(unique_key) ~= "table" then
    error("unique_key must be a table", 2)
  end

  local message = fmt("UNIQUE violation detected on '%s'",
                      pl_pretty(unique_key, ""):gsub("\"userdata: NULL\"", "null"))

  return new_err_t(self, ERRORS.UNIQUE_VIOLATION, message, unique_key)
end


function _M:not_found(primary_key)
  if type(primary_key) ~= "table" then
    error("primary_key must be a table", 2)
  end

  local message = fmt("could not find the entity with primary key '%s'",
                      pl_pretty(primary_key, ""))

  return new_err_t(self, ERRORS.NOT_FOUND, message, primary_key)
end


function _M:not_found_by_field(filter)
  if type(filter) ~= "table" then
    error("filter must be a table", 2)
  end

  local message = fmt("could not find the entity with '%s'",
                      pl_pretty(filter, ""))

  return new_err_t(self, ERRORS.NOT_FOUND, message, filter)
end


function _M:invalid_offset(offset, err)
  if type(offset) ~= "string" then
    error("offset must be a string", 2)
  end

  if type(err) ~= "string" then
    error("err must be a string", 2)
  end

  local message = fmt("'%s' is not a valid offset: %s", offset, err)

  return new_err_t(self, ERRORS.INVALID_OFFSET, message)
end


function _M:database_error(err)
  err = err or ERRORS_NAMES[ERRORS.DATABASE_ERROR]
  return new_err_t(self, ERRORS.DATABASE_ERROR, err)
end


function _M:transformation_error(err)
  err = err or ERRORS_NAMES[ERRORS.TRANSFORMATION_ERROR]
  return new_err_t(self, ERRORS.TRANSFORMATION_ERROR, err)
end


function _M:invalid_size(err)
  if type(err) ~= "string" then
    error("err must be a string", 2)
  end

  return new_err_t(self, ERRORS.INVALID_SIZE, err)
end


function _M:invalid_unique(name, err)
  if type(err) ~= "string" then
    error("err must be a string", 2)
  end

  return new_err_t(self, ERRORS.INVALID_UNIQUE, err, nil,
                   fmt(ERRORS_NAMES[ERRORS.INVALID_UNIQUE], name))
end


function _M:invalid_options(errors)
  if type(errors) ~= "table" then
    error("errors must be a table", 2)
  end

  local buf = {}
  local len = 0

  for _, option_name in ipairs(sorted_keys(errors)) do
    local option_errors = errors[option_name]
    if type(option_errors) == "table" then
      for _, sub_option in ipairs(sorted_keys(option_errors)) do
        len = len + 1
        buf[len] = fmt("%s.%s: %s", option_name, sub_option,
                       option_errors[sub_option])
      end

    else
      len = len + 1
      buf[len] = fmt("%s: %s", option_name, option_errors)
    end
  end

  local message

  if len == 1 then
    message = fmt("invalid option (%s)", buf[1])

  else
    message = fmt("%d option violations (%s)",
                  len, concat(buf, "; "))
  end

  return new_err_t(self, ERRORS.INVALID_OPTIONS, message, errors)
end


function _M:operation_unsupported(err)
  if type(err) ~= "string" then
    error("err must be a string", 2)
  end

  return new_err_t(self, ERRORS.OPERATION_UNSUPPORTED, err)
end


function _M:declarative_config(err_t)
  if type(err_t) ~= "table" then
    error("err_t must be a table", 2)
  end

  local message = fmt("declarative config is invalid: %s",
                      pl_pretty(err_t, ""))

  return new_err_t(self, ERRORS.DECLARATIVE_CONFIG, message, err_t)
end


return _M
