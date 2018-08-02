local utils = require "kong.tools.utils"

local POSSIBLE_TYPES = {
  url = true,
  table = true,
  array = true,
  string = true,
  number = true,
  boolean = true,
  timestamp = true,
}

local custom_types_validation = {
  ["url"] = function(v)
    if v and type(v) == "string" then
      local parsed_url = require("socket.url").parse(v)
      if parsed_url and not parsed_url.path then
        parsed_url.path = "/"
      end
      return parsed_url and parsed_url.path and parsed_url.host and parsed_url.scheme
    end
  end,
  ["array"] = function(v)
    return utils.is_array(v)
  end,
  ["timestamp"] = function(v)
    return v and v > 0
  end,
}

local function validate_type(field_type, value)
  if custom_types_validation[field_type] then
    return custom_types_validation[field_type](value)
  end
  return type(value) == field_type
end

local function validate_array(v, tbl, column)
  -- Handle empty arrays
  if utils.strip(tbl[column]) == "" then
    tbl[column] = {}
    return true
  end
  -- handle escaped commas inside the comma-separated array
  -- by flipping them into a \0 and then back
  local escaped = tbl[column]:gsub("\\,", "\0")
  tbl[column] = utils.split(escaped, ",")
  for arr_k, arr_v in ipairs(tbl[column]) do
    tbl[column][arr_k] = utils.strip(arr_v):gsub("%z", ",")
  end
  return validate_type(v.type, tbl[column])
end

local _M = {}

--- Validate a table against a given schema.
-- @param[type=table] tbl A table representing the entity to validate.
-- @param[type=table] schema Schema against which to validate the entity.
-- @param[type=table] options (**Optional**) Can contain a `dao_insert` field, which will be called
-- for each schema field with a `dao_insert_value` property. An `update` boolean, if the validation
-- is performed during an update of the entity, and a `full_update` boolean, if the validaiton is
-- performed during a full update of the entity.
-- @treturn boolean `ok`: A boolean describing if the entity was valid not not.
-- @treturn table `errors`: A list of errors describing the invalid properties of the entity. Those errors
-- are purely related to schema validation, unlike the third return value.
-- @treturn table `self_check_error`: If any, an error returned by the `self_check` function of a schema.
-- This error is not returned in the second return value because it might be unrelated to schema validation,
-- and hence have a different error type (DB error for example).
function _M.validate_entity(tbl, schema, options)
  if not options then
    options = {}
  end
  if not options.old_t then
    options.old_t = {}
  end

  local errors
  local partial_update = options.update and not options.full_update

  local key_values = {[""] = tbl} -- By default is only one element

  if schema.flexible then
    for k,v in pairs(tbl) do
      key_values[k] = v -- Add all the flexible values to the array
    end
  end

  for tk, t in pairs(key_values) do
    if t ~= nil then
      local error_prefix = ""
      if utils.strip(tk) ~= "" then
        error_prefix = tk .. "."
      end

      if schema.flexible and type(t) ~= "table" then
        errors = utils.add_error(errors, tk, tk .. " is not a table")
        break
      end

      if not partial_update then
        for column, v in pairs(schema.fields) do
          if t[column] == ngx.null then
            t[column] = nil
          end
          -- [DEFAULT] Set default value for the field if given
          if t[column] == nil and v.default ~= nil then
            if type(v.default) == "function" then
              t[column] = v.default(t)
            else
              t[column] = utils.deep_copy(v.default)
            end
          end
        end
      end

      -- Check the given table against a given schema

      for column, v in pairs(schema.fields) do
        if not partial_update then
          if t[column] == ngx.null then
            t[column] = nil
          end
        end

        -- [TYPE] Check if type is valid. Booleans and Numbers as strings are accepted and converted
        if t[column] ~= nil and t[column] ~= ngx.null and v.type ~= nil then
          local is_valid_type
          -- ALIASES: number, timestamp, boolean and array can be passed as strings and will be converted
          if type(t[column]) == "string" then
            if schema.fields[column].trim_whitespace ~= false then
              t[column] = utils.strip(t[column])
            end
            if v.type == "boolean" then
              local bool = t[column]:lower()
              is_valid_type = bool == "true" or bool == "false"
              t[column] = bool == "true"
            elseif v.type == "array" then
              is_valid_type = validate_array(v, t, column)
            elseif v.type == "number" or v.type == "timestamp" then
              t[column] = tonumber(t[column])
              is_valid_type = validate_type(v.type, t[column])
            else -- if string
              is_valid_type = validate_type(v.type, t[column])
            end
          else
            is_valid_type = validate_type(v.type, t[column])
          end

          if not is_valid_type and POSSIBLE_TYPES[v.type] then
            errors = utils.add_error(errors, error_prefix .. column,
                    string.format("%s is not %s %s", column, v.type == "array" and "an" or "a", v.type))
            goto continue
          end
        end

        -- [IMMUTABLE] check immutability of a field if updating
        if v.immutable and options.update and (t[column] ~= nil and options.old_t[column] ~= nil and t[column] ~= options.old_t[column]) and not v.required then
          errors = utils.add_error(errors, error_prefix .. column, column .. " cannot be updated")
        end

        -- [ENUM] Check if the value is allowed in the enum.
        if t[column] ~= nil and t[column] ~= ngx.null and v.enum ~= nil then
          local found = true
          local wrong_value = t[column]
          if v.type == "array" then
            for _, array_value in ipairs(t[column]) do
              if not utils.table_contains(v.enum, array_value) then
                found = false
                wrong_value = array_value
                break
              end
            end
          else
            found = utils.table_contains(v.enum, t[column])
          end

          if not found then
            errors = utils.add_error(errors, error_prefix .. column, string.format("\"%s\" is not allowed. Allowed values are: \"%s\"", wrong_value, table.concat(v.enum, "\", \"")))
          end
        end

        -- [REGEX] Check field against a regex if specified
        if type(t[column]) == "string" and v.regex then
          if not ngx.re.find(t[column], v.regex) then
            errors = utils.add_error(errors, error_prefix .. column, column .. " has an invalid value")
          end
        end

        -- [SCHEMA] Validate a sub-schema from a table or retrieved by a function
        if v.schema then
          local sub_schema, err
          if type(v.schema) == "function" then
            sub_schema, err = v.schema(t)
            if err then -- could not retrieve sub schema
              errors = utils.add_error(errors, error_prefix .. column, err)
            end
          else
            sub_schema = v.schema
          end

          if sub_schema then
            -- Check for sub-schema defaults and required properties in advance
            if t[column] == nil then
              for sub_field_k, sub_field in pairs(sub_schema.fields) do
                if sub_field.default ~= nil then -- Sub-value has a default, be polite and pre-assign the sub-value
                  t[column] = {}
                elseif sub_field.required then -- Only check required if field doesn't have a default and dao_insert_value
                  errors = utils.add_error(errors, error_prefix .. column, column .. "." .. sub_field_k .. " is required")
                end
              end
            end

            if t[column] and t[column] ~= ngx.null and type(t[column]) == "table" then
              -- Actually validating the sub-schema
              local s_ok, s_errors, s_self_check_err = _M.validate_entity(t[column], sub_schema, options)
              if not s_ok then
                if s_self_check_err then
                  errors = utils.add_error(errors, error_prefix .. column .. (tk ~= "" and "." .. tk or ""), s_self_check_err.message)
                else
                  for s_k, s_v in pairs(s_errors) do
                    errors = utils.add_error(errors, error_prefix .. column .. "." .. s_k, s_v)
                  end
                end
              end
            end
          end
        end

        -- Check that full updates still meet the REQUIRED contraints
        if options.full_update and v.required and (t[column] == nil or t[column] == "") then
          errors = utils.add_error(errors, error_prefix .. column, column .. " is required")
        end

        if not partial_update or t[column] ~= nil then
          -- [REQUIRED] Check that required fields are set.
          -- Now that default and most other checks have been run.
          if not options.full_update and v.required and not v.dao_insert_value and (t[column] == nil or t[column] == "" or t[column] == ngx.null) then
            errors = utils.add_error(errors, error_prefix .. column, column .. " is required")
          end

          local callable = type(v.func) == "function"
          if not callable then
            local mt = getmetatable(v.func)
            callable = mt and mt.__call ~= nil
          end
          if callable and (errors == nil or errors[column] == nil) then
            -- [FUNC] Check field against a custom function
            -- only if there is no error on that field already.
            local ok, err, new_fields
            if t[column] == ngx.null then
              ok, err, new_fields = v.func(nil, t, column)
            else
              ok, err, new_fields = v.func(t[column], t, column)
            end
            if ok == false and err then
              errors = utils.add_error(errors, error_prefix .. column, err)
            elseif new_fields then
              for k, v in pairs(new_fields) do
                t[k] = v
              end
            end
          end
        end

        ::continue::
      end

      -- Check for unexpected fields in the entity
      for k in pairs(t) do
        if schema.fields[k] == nil then
          if schema.flexible then
            if utils.strip(tk) ~= "" and k ~= tk then
              errors = utils.add_error(errors, error_prefix .. k, k .. " is an unknown field")
            end
          else
            errors = utils.add_error(errors, error_prefix .. k, k .. " is an unknown field")
          end
        end
      end

      if errors == nil and type(schema.self_check) == "function" then
        local nil_c = {}
        for column in pairs(schema.fields) do
          if t[column] == ngx.null then
            t[column] = nil
            table.insert(nil_c, column)
          end
        end
        local ok, err = schema.self_check(schema, t, options.dao, options.update)
        if ok == false then
          return false, nil, err
        end
        for _, column in ipairs(nil_c) do
          t[column] = ngx.null
        end
      end
    end
  end

  return errors == nil, errors
end

function _M.is_schema_subset(tbl, schema)
  local errors

  for k, v in pairs(tbl) do
    if schema.fields[k] == nil then
      errors = utils.add_error(errors, k, "unknown field")
    elseif schema.fields[k].type == "id" and v ~= nil then
      if not utils.is_valid_uuid(v) then
        errors = utils.add_error(errors, k, tostring(v) .. " is not a valid uuid")
      end
    end
  end

  return errors == nil, errors
end

return _M
