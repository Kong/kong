-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_template = require "pl.template"
local tx = require "pl.tablex"
local typedefs = require "kong.db.schema.typedefs"

local ngx_re = require("ngx.re")
local re_match = ngx.re.match


-- entries must have colons to set the key and value apart
local function check_for_value(entry)
  local name, value = entry:match("^([^:]+):*(.-)$")
  if not name or not value or value == "" then
    return false, "key '" ..name.. "' has no value"
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
  local res = ngx_re.split(path, "\\.")
  for i = 1, #res do
    -- not allow: 1. consecutive dots; 2. elements start with '[.*]'
    if res[i] == '' or re_match(res[i], "^\\[.*\\]") then
      return false
    else
      local captures = re_match(res[i], "\\[(.*)\\]")
      if captures then
        if captures[1] then
          -- not allow: illegal indexes
          if re_match(captures[1], "^[\\d+|\\*]$") == nil then
            return false
          end
        end
      end
    end
  end
  return true
end

local function check_for_body(record)
  local body = record.body
  if body ~= nil and #body > 0 then
    for i = 1, #body do
      if not check_for_path(body[i]) then
        return false, "unsupported value '" .. body[i] .. "' in body field"
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
  custom_validator = check_for_body,
}


local colon_strings_array = {
  type = "array",
  default = {},
  elements = {
    type = "string",
    custom_validator = check_for_value,
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
  custom_validator = check_for_body,
}

local colon_strings_array_record_plus_json_types = tx.deepcopy(colon_strings_array_record)
local json_types = { json_types = json_types_array }
table.insert(colon_strings_array_record_plus_json_types.fields, json_types)


local colon_strings_array_record_plus_json_types_uri = tx.deepcopy(colon_strings_array_record_plus_json_types)
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
          { dots_in_keys = { type = "boolean", default = true }, },
        },
      },
    },
  },
}
