--- A library of ready-to-use type synonyms to use in schema definitions.
-- @module kong.db.schema.typedefs
local utils = require "kong.tools.utils"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"
local iputils = require "resty.iputils"
local Schema = require("kong.db.schema")
local socket_url = require("socket.url")
local constants = require "kong.constants"


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


local function validate_ip(ip)
  local res, err = utils.normalize_ip(ip)
  if not res then
    return nil, err
  end

  if res.type == "name" then
    return nil, "not an ip address: " .. ip
  end

  return true
end


local function validate_cidr(ip)
  local _, err = iputils.parse_cidr(ip)

  -- It's an error only if the second variable is a string
  if type(err) == "string" then
    return nil, "invalid cidr range: " .. err
  end

  return true
end


local function validate_path(path)
  -- Accept '$''{''}' and all characters defined in RFC 3986
  if not match(path, "^/[%w%.%-%_~%/%%${}]*$") then
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


local function validate_sni(host)
  local res, err_or_port = utils.normalize_ip(host)
  if type(err_or_port) == "string" and err_or_port ~= "invalid port number" then
    return nil, "invalid value: " .. host
  end

  if res.type ~= "name" then
    return nil, "must not be an IP"
  end

  if err_or_port == "invalid port number" or type(res.port) == "number" then
    return nil, "must not have a port"
  end

  return true
end


local function validate_url(url)
  local parsed_url, err = socket_url.parse(url)

  if not parsed_url then
    return nil, "could not parse url. " .. err
  end

  if not parsed_url.host then
    return nil, "missing host in url"
  end

  if not parsed_url.scheme then
    return nil, "missing scheme in url"
  end

  return true
end


local function validate_certificate(cert)
  local ok
  ok, cert = pcall(openssl_x509.new, cert)
  if not ok then
    return nil, "invalid certificate: " .. cert
  end

  return true
end


local function validate_key(key)
  local ok
  ok, key = pcall(openssl_pkey.new, key)
  if not ok then
    return nil, "invalid key: " .. key
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
  one_of = constants.PROTOCOLS,
}


typedefs.host = Schema.define {
  type = "string",
  custom_validator = validate_host,
}


typedefs.ip = Schema.define {
  type = "string",
  custom_validator = validate_ip,
}


typedefs.cidr = Schema.define {
  type = "string",
  custom_validator = validate_cidr,
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

typedefs.url = Schema.define {
  type = "string",
  custom_validator = validate_url,
}

typedefs.header_name = Schema.define {
  type = "string",
  custom_validator = utils.validate_header_name,
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


typedefs.sni = Schema.define {
  type = "string",
  custom_validator = validate_sni,
}


typedefs.certificate = Schema.define {
  type = "string",
  custom_validator = validate_certificate,
}


typedefs.key = Schema.define {
  type = "string",
  custom_validator = validate_key,
}


typedefs.run_on = Schema.define {
  type = "string",
  required = true,
  default = "first",
  one_of = { "first", "second", "all" },
}

typedefs.run_on_first = Schema.define {
  type = "string",
  required = true,
  default = "first",
  one_of = { "first" },
}

typedefs.tag = Schema.define {
  type = "string",
  required = true,
  match = "^[%w%.%-%_~]+$",
}

typedefs.tags = Schema.define {
  type = "set",
  elements = typedefs.tag,
}

local http_protocols = {}
for p, s in pairs(constants.PROTOCOLS_WITH_SUBSYSTEM) do
  if s == "http" then
    http_protocols[#http_protocols + 1] = p
  end
end
table.sort(http_protocols)

typedefs.protocols = Schema.define {
  type = "set",
  required = true,
  default = http_protocols,
  elements = typedefs.protocol,
}

typedefs.protocols_http = Schema.define {
  type = "set",
  required = true,
  default = http_protocols,
  elements = { type = "string", one_of = http_protocols },
}

setmetatable(typedefs, {
  __index = function(_, k)
    error("schema typedef error: definition " .. k .. " does not exist", 2)
  end
})


return typedefs
