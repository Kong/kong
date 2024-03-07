-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_template = require "pl.template"
local utils = require "kong.tools.utils"
local typedefs = require "kong.db.schema.typedefs"

local ngx_re = require("ngx.re")
local re_match = ngx.re.match


-- entries must have colons to set the key and value apart
local function check_for_value(entry)
  local name, value = entry:match("^([^:]+):*(.-)$")
  if not name or not value or value == "" then
    return false, "key '" .. name .. "' has no value"
  end

  local status, res, err = pcall(pl_template.compile, value)
  if not status or err then
    return false, "value '" .. value ..
            "' is not in supported format, error:" ..
            (status and res or err)
  end

  return true
end

local function check_for_path(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local res = ngx_re.split(path, "\\.")
  for i = 1, #res do
    -- don't allow: 1. consecutive dots; 2. elements start with '[.*]'
    if res[i] == '' or re_match(res[i], "^\\[.*\\]") then
      return false

    else
      local captures = re_match(res[i], "\\[(.*)\\]")
      if captures then
        if captures[1] then
          -- don't allow: illegal indexes
          if re_match(captures[1], "^[\\d+|\\*]$") == nil then
            return false
          end
        end
      end
    end
  end
  return true
end

local function check_for_body(bodies, operation)
  -- elements in bodies should match such pattern: `first:last` unless operation is `remove`
  local first, last
  if type(bodies) ~= "table" then
    return false, "unsupported type '" .. type(bodies) .. "' for body field"
  end

  for _, body in ipairs(bodies) do
    if type(body) ~= "string" or body == "" then
      return false, "elements in body field should be non empty strings"
    end

    first, last = body:match("^([^:]+):*(.-)$")
    if not check_for_path(first) then
      return false, "unsupported value '" .. body .. "' in body field"
    end

    if operation == "rename" then
      -- the `last` should also be checked to ensure it's also a valid path if operation is `rename
      if not check_for_path(last) then
        return false, "unsupported value '" .. body .. "' in body field"
      end
    end
  end

  return true
end

local operations = {"remove", "rename", "replace", "add", "append"}
local field_typies = {"headers", "querystring", "body"}

local function check_for_operation(config, operation)
  if config.body then
    local ok, err = check_for_body(config.body, operation)
    if not ok then
      return ok, { body = { err } }
    end
  end

  if operation ~= "remove" then
    for _, field_typs in ipairs(field_typies) do
      if config[field_typs] then
        for _, v in ipairs(config[field_typs]) do
          local ok, err = check_for_value(v)
          if not ok then
            return ok, { [field_typs] = { err } }
          end
        end
      end
    end
  end

  return true
end

local function check_for_config(config)
  for _, op in ipairs(operations) do
    if config[op] ~= nil then
      local ok, err = check_for_operation(config[op], op)
      if not ok then
        return ok, { [op] = err }
      end
    end
  end

  return true
end


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
}

local json_types_array = {
  type = "array",
  default = {},
  elements = {
    type = "string",
    one_of = { "boolean", "number", "string" }
  }
}

local strings_array_record = {
  type = "record",
  fields = {
    { body = strings_array },
    { headers = strings_array },
    { querystring = strings_array },
  },
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = {
    type = "string",
    referenceable = true,
  }
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_strings_array },
    { querystring = colon_strings_array },
  },
}

local colon_strings_array_record_plus_json_types = utils.cycle_aware_deep_copy(colon_strings_array_record)
local json_types = { json_types = json_types_array }
table.insert(colon_strings_array_record_plus_json_types.fields, json_types)


local colon_strings_array_record_plus_json_types_uri = utils.cycle_aware_deep_copy(colon_strings_array_record_plus_json_types)
local uri = { uri = { type = "string" } }
table.insert(colon_strings_array_record_plus_json_types_uri.fields, uri)


local strings_set = {
  type = "set",
  elements = { type = "string" },
}

local strings_set_record = {
  type = "record",
  fields = {
    { body = strings_set },
  },
}


return {
  name = "request-transformer-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { http_method = typedefs.http_method },
          { remove  = strings_array_record },
          { rename  = colon_strings_array_record },
          { replace = colon_strings_array_record_plus_json_types_uri },
          { add     = colon_strings_array_record_plus_json_types },
          { append  = colon_strings_array_record_plus_json_types },
          { allow   = strings_set_record },
          { dots_in_keys = { description = "Specify whether dots (for example, `customers.info.phone`) should be treated as part of a property name or used to descend into nested JSON objects.  See [Arrays and nested objects](#arrays-and-nested-objects).", type = "boolean", default = true }, },
        },
        custom_validator = check_for_config,
      },
    },
  },
}