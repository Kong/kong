--- A library of ready-to-use type synonyms to use in schema definitions.
-- @module kong.db.schema.typedefs
local utils = require "kong.tools.utils"

local typedefs = {}
local Schema = require("kong.db.schema")


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
  if not string.match(path, "^/[%w%.%-%_~%/%%]*$") then
    return nil,
           "invalid path: '" .. path ..
           "' (characters outside of the reserved list of RFC 3986 found)",
           "rfc3986"
  end

  do
    -- ensure it is properly percent-encoded
    local raw = string.gsub(path, "%%%x%x", "___")

    if raw:find("%", nil, true) then
      local err = raw:sub(raw:find("%%.?.?"))
      return nil, "invalid url-encoded value: '" .. err .. "'"
    end
  end

  return true
end


typedefs.http_method = Schema.define {
  type = "string",
  match = "^%u+$",
}

typedefs.protocol = Schema.define {
  type = "string",
  one_of = {
    "http",
    "https"
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

return typedefs
