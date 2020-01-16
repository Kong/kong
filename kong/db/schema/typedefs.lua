--- A library of ready-to-use type synonyms to use in schema definitions.
-- @module kong.db.schema.typedefs
local utils = require "kong.tools.utils"
local openssl_pkey = require "resty.openssl.pkey"
local openssl_x509 = require "resty.openssl.x509"
local iputils = require "resty.iputils"
local Schema = require("kong.db.schema")
local socket_url = require("socket.url")
local constants = require "kong.constants"
local px = require "resty.mediador.proxy"


local pairs = pairs
local pcall = pcall
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


local function validate_host_with_optional_port(host)
  local res, err_or_port = utils.normalize_ip(host)
  return (res and true or nil), err_or_port
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


local function validate_ip_or_cidr(ip)
  local pok, perr = pcall(px.compile, ip)

  if pok and type(perr) == "function" then
    return true
  end

  return nil, "invalid ip or cidr range: '" .. ip .. "'"
end


local function validate_cidr_v4(ip)
  local _, err = iputils.parse_cidr(ip)

  -- It's an error only if the second variable is a string
  if type(err) == "string" then
    return nil, "invalid cidr range: " .. err
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


local function validate_wildcard_host(host)
  local idx = string.find(host, "*", nil, true)
  if idx then
    if idx ~= 1 and idx ~= #host then
      return nil, "wildcard must be leftmost or rightmost character"
    end

    -- substitute wildcard for upcoming host normalization
    local mock_host, count = string.gsub(host, "%*", "wildcard")
    if count > 1 then
      return nil, "only one wildcard must be specified"
    end

    host = mock_host
  end

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
  local _, err =  openssl_x509.new(cert)
  if err then
    return nil, "invalid certificate: " .. err
  end

  return true
end


local function validate_key(key)
  local _, err =  openssl_pkey.new(key)
  if err then
    return nil, "invalid key: " .. err
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


typedefs.host_with_optional_port = Schema.define {
  type = "string",
  custom_validator = validate_host_with_optional_port,
}


typedefs.wildcard_host = Schema.define {
  type = "string",
  custom_validator = validate_wildcard_host,
}


typedefs.ip = Schema.define {
  type = "string",
  custom_validator = validate_ip,
}

typedefs.ip_or_cidr = Schema.define {
  type = "string",
  custom_validator = validate_ip_or_cidr,
}

typedefs.cidr_v4 = Schema.define {
  type = "string",
  custom_validator = validate_cidr_v4,
}

-- deprecated alias
typedefs.cidr = typedefs.cidr_v4

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


-- routes typedefs
-- common for routes and routes subschemas

local function validate_host_with_wildcards(host)
  local no_wildcards = string.gsub(host, "%*", "abc")
  return typedefs.host_with_optional_port.custom_validator(no_wildcards)
end

local function validate_path_with_regexes(path)


  local ok, err, err_code = typedefs.path.custom_validator(path)

  if ok or err_code ~= "rfc3986" then
    return ok, err, err_code
  end

  -- URI contains characters outside of the reserved list of RFC 3986:
  -- the value will be interpreted as a regex by the router; but is it a
  -- valid one? Let's dry-run it with the same options as our router.
  local _, _, err = ngx.re.find("", path, "aj")
  if err then
    return nil,
           string.format("invalid regex: '%s' (PCRE returned: %s)",
                         path, err)
  end

  return true
end


typedefs.sources = Schema.define {
  type = "set",
  elements = {
    type = "record",
    fields = {
      { ip = typedefs.ip_or_cidr },
      { port = typedefs.port },
    },
    entity_checks = {
      { at_least_one_of = { "ip", "port" } }
    },
  },
}

typedefs.no_sources = Schema.define(typedefs.sources { eq = null })

typedefs.destinations = Schema.define {
  type = "set",
  elements = {
    type = "record",
    fields = {
      { ip = typedefs.ip_or_cidr },
      { port = typedefs.port },
    },
    entity_checks = {
      { at_least_one_of = { "ip", "port" } }
    },
  },
}

typedefs.no_destinations = Schema.define(typedefs.destinations { eq = null })

typedefs.methods = Schema.define {
  type = "set",
  elements = typedefs.http_method,
}

typedefs.no_methods = Schema.define(typedefs.methods { eq = null })

typedefs.hosts = Schema.define {
  type = "array",
  elements = {
    type = "string",
    match_all = {
      {
        pattern = "^[^*]*%*?[^*]*$",
        err = "invalid wildcard: must have at most one wildcard",
      },
    },
    match_any = {
      patterns = { "^%*%.", "%.%*$", "^[^*]*$" },
      err = "invalid wildcard: must be placed at leftmost or rightmost label",
    },
    custom_validator = validate_host_with_wildcards,
  }
}

typedefs.no_hosts = Schema.define(typedefs.hosts { eq = null })

typedefs.paths = Schema.define {
  type = "array",
  elements = typedefs.path {
    custom_validator = validate_path_with_regexes,
    match_none = {
      {
        pattern = "//",
        err = "must not have empty segments"
      },
    },
  }
}

typedefs.no_paths = Schema.define(typedefs.paths { eq = null })

typedefs.headers = Schema.define {
  type = "map",
  keys = {
    type = "string",
    match_none = {
      {
        pattern = "^[Hh][Oo][Ss][Tt]$",
        err = "cannot contain 'host' header, which must be specified in the 'hosts' attribute",
      },
    },
  },
  values = {
    type = "array",
    elements = {
      type = "string",
    },
  },
}

typedefs.no_headers = Schema.define(typedefs.headers { eq = null } )

setmetatable(typedefs, {
  __index = function(_, k)
    error("schema typedef error: definition " .. k .. " does not exist", 2)
  end
})


return typedefs
