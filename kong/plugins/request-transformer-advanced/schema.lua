local pl_template = require "pl.template"
local tx = require "pl.tablex"
local typedefs = require "kong.db.schema.typedefs"

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


local strings_array = {
  type = "array",
  default = {},
  elements = { type = "string" },
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
  elements = { type = "string", custom_validator = check_for_value }
}


local colon_strings_array_record = {
  type = "record",
  fields = {
    { body = colon_strings_array },
    { headers = colon_strings_array },
    { querystring = colon_strings_array },
  },
}


local colon_strings_array_record_plus_uri = tx.deepcopy(colon_strings_array_record)
local uri = { uri = { type = "string" } }
table.insert(colon_strings_array_record_plus_uri.fields, uri)


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
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { http_method = typedefs.http_method },
          { remove  = strings_array_record },
          { rename  = colon_strings_array_record },
          { replace = colon_strings_array_record_plus_uri },
          { add     = colon_strings_array_record },
          { append  = colon_strings_array_record },
          { whitelist  = strings_set_record },
        }
      },
    },
  }
}
