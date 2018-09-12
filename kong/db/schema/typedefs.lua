--- A library of ready-to-use type synonyms to use in schema definitions.
-- @module kong.db.schema.typedefs
local utils = require "kong.tools.utils"
local Schema = require("kong.db.schema")


local match = string.match
local gsub = string.gsub
local null = ngx.null
local type = type


local function validate_host(host)
  local res, err_or_port = utils.normalize_ip(host)
  if type(err_or_port) == "string" and err_or_port ~= "invalid port number" then
    return nil, "invalid value: " .. host
  end

  if err_or_port == "invalid port number" or type(res.port) == "number" then
    return nil, "must not have a port"
  end

  return true
end


local function validate_path(path)
  if not match(path, "^/[%w%.%-%_~%/%%]*$") then
    return nil,
           "invalid path: '" .. path ..
           "' (characters outside of the reserved list of RFC 3986 found)",
           "rfc3986"
  end

  do
    -- ensure it is properly percent-encoded
    local raw = gsub(path, "%%%x%x", "___")

    if raw:find("%", nil, true) then
      local err = raw:sub(raw:find("%%.?.?"))
      return nil, "invalid url-encoded value: '" .. err .. "'"
    end
  end

  return true
end


local function validate_name(name)
  if not match(name, "^[%w%.%-%_~]+$") then
    return nil,
    "invalid value '" .. name ..
      "': it must only contain alphanumeric and '., -, _, ~' characters"
  end

  return true
end


local typedefs = {}


typedefs.http_method = Schema.define {
  type = "string",
  match = "^%u+$",
}


typedefs.protocol = Schema.define {
  type = "string",
  one_of = {
    "http",
    "https",
  }
}


typedefs.host = Schema.define {
  type = "string",
  custom_validator = validate_host,
}


typedefs.port = Schema.define {
  type = "integer",
  between = { 0, 65535 }
}


typedefs.path = Schema.define {
  type = "string",
  starts_with = "/",
  match_none = {
    { pattern = "//",
      err = "must not have empty segments"
    },
  },
  custom_validator = validate_path,
}


typedefs.timeout = Schema.define {
  type = "integer",
  between = { 0, math.pow(2, 31) - 2 },
}


typedefs.uuid = Schema.define {
  type = "string",
  uuid = true,
  auto = true,
}


typedefs.auto_timestamp_s = Schema.define {
  type = "integer",
  timestamp = true,
  auto = true
}


typedefs.auto_timestamp_ms = Schema.define {
  type = "number",
  timestamp = true,
  auto = true
}


typedefs.no_api = Schema.define {
  type = "foreign",
  reference = "apis",
  eq = null,
}


typedefs.no_route = Schema.define {
  type = "foreign",
  reference = "routes",
  eq = null,
}


typedefs.no_service = Schema.define {
  type = "foreign",
  reference = "services",
  eq = null,
}


typedefs.no_consumer = Schema.define {
  type = "foreign",
  reference = "consumers",
  eq = null,
}


typedefs.name = Schema.define {
  type = "string",
  unique = true,
  custom_validator = validate_name
}


return typedefs
