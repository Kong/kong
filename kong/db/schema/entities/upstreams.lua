local Schema = require "kong.db.schema"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"
local null = ngx.null


local function get_name_for_error(name)
  local ok = utils.validate_utf8(name)
  if not ok then
    return "Invalid name"
  end

  return "Invalid name ('" .. name .. "')"
end


local validate_name = function(name)
  local p = utils.normalize_ip(name)
  if not p then
    return nil, get_name_for_error(name) .. "; must be a valid hostname"
  end
  if p.type ~= "name" then
    return nil, get_name_for_error(name) .. "; no ip addresses allowed"
  end
  if p.port then
    return nil, get_name_for_error(name) .. "; no port allowed"
  end
  return true
end


local hash_on = Schema.define {
  type = "string",
  default = "none",
  one_of = { "none", "consumer", "ip", "header", "cookie" }
}


local http_statuses = Schema.define {
  type = "array",
  elements = { type = "integer", between = { 100, 999 }, },
}


local seconds = Schema.define {
  type = "number",
  between = { 0, 65535 },
}


local positive_int = Schema.define {
  type = "integer",
  between = { 1, 2 ^ 31 },
}


local one_byte_integer = Schema.define {
  type = "integer",
  between = { 0, 255 },
}


local check_type = Schema.define {
  type = "string",
  one_of = { "tcp", "http", "https", "grpc", "grpcs" },
  default = "http",
}


local check_verify_certificate = Schema.define {
  type = "boolean",
  default = true,
  required = true,
}


local health_threshold = Schema.define {
  type = "number",
  default = 0,
  between = { 0, 100 },
}


local NO_DEFAULT = {}


local healthchecks_config = {
  active = {
    type = "http",
    timeout = 1,
    concurrency = 10,
    http_path = "/",
    https_sni = NO_DEFAULT,
    https_verify_certificate = true,
    healthy = {
      interval = 0,  -- 0 = probing disabled by default
      http_statuses = { 200, 302 },
      successes = 0, -- 0 = disabled by default
    },
    unhealthy = {
      interval = 0, -- 0 = probing disabled by default
      http_statuses = { 429, 404,
                        500, 501, 502, 503, 504, 505 },
      tcp_failures = 0,  -- 0 = disabled by default
      timeouts = 0,      -- 0 = disabled by default
      http_failures = 0, -- 0 = disabled by default
    },
  },
  passive = {
    type = "http",
    healthy = {
      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                        300, 301, 302, 303, 304, 305, 306, 307, 308 },
      successes = 0,
    },
    unhealthy = {
      http_statuses = { 429, 500, 503 },
      tcp_failures = 0,  -- 0 = circuit-breaker disabled by default
      timeouts = 0,      -- 0 = circuit-breaker disabled by default
      http_failures = 0, -- 0 = circuit-breaker disabled by default
    },
  },
}


local types = {
  type = check_type,
  timeout = seconds,
  concurrency = positive_int,
  interval = seconds,
  successes = one_byte_integer,
  tcp_failures = one_byte_integer,
  timeouts = one_byte_integer,
  http_failures = one_byte_integer,
  http_path = typedefs.path,
  http_statuses = http_statuses,
  https_sni = typedefs.sni,
  https_verify_certificate = check_verify_certificate,
}


local function gen_fields(tbl)
  local fields = {}
  local count = 0
  for name, default in pairs(tbl) do
    local typ = types[name]
    local def, required
    if default == NO_DEFAULT then
      default = nil
      required = false
      tbl[name] = nil
    end
    if typ then
      def = typ{ default = default, required = required }
    else
      def = { type = "record", fields = gen_fields(default), default = default }
    end
    count = count + 1
    fields[count] = { [name] = def }
  end
  return fields, tbl
end


local healthchecks_fields, healthchecks_defaults = gen_fields(healthchecks_config)
healthchecks_fields[#healthchecks_fields+1] = { ["threshold"] = health_threshold }


local r =  {
  name = "upstreams",
  primary_key = { "id" },
  endpoint_key = "name",
  workspaceable = true,
  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { name = { type = "string", required = true, unique = true, custom_validator = validate_name }, },
    { algorithm = { type = "string",
        default = "round-robin",
        one_of = { "consistent-hashing", "least-connections", "round-robin" },
    }, },
    { hash_on = hash_on },
    { hash_fallback = hash_on },
    { hash_on_header = typedefs.header_name, },
    { hash_fallback_header = typedefs.header_name, },
    { hash_on_cookie = { type = "string",  custom_validator = utils.validate_cookie_name }, },
    { hash_on_cookie_path = typedefs.path{ default = "/", }, },
    { slots = { type = "integer", default = 10000, between = { 10, 2^16 }, }, },
    { healthchecks = { type = "record",
        default = healthchecks_defaults,
        fields = healthchecks_fields,
    }, },
    { tags = typedefs.tags },
    { host_header = typedefs.host_with_optional_port },
    { client_certificate = { type = "foreign", reference = "certificates" }, },
  },
  entity_checks = {
    -- hash_on_header must be present when hashing on header
    { conditional = {
      if_field = "hash_on", if_match = { match = "^header$" },
      then_field = "hash_on_header", then_match = { required = true },
    }, },
    { conditional = {
      if_field = "hash_fallback", if_match = { match = "^header$" },
      then_field = "hash_fallback_header", then_match = { required = true },
    }, },

    -- hash_on_cookie must be present when hashing on cookie
    { conditional = {
      if_field = "hash_on", if_match = { match = "^cookie$" },
      then_field = "hash_on_cookie", then_match = { required = true },
    }, },
    { conditional = {
      if_field = "hash_fallback", if_match = { match = "^cookie$" },
      then_field = "hash_on_cookie", then_match = { required = true },
    }, },

    -- hash_fallback must be "none" if hash_on is "none"
    { conditional = {
      if_field = "hash_on", if_match = { match = "^none$" },
      then_field = "hash_fallback", then_match = { one_of = { "none" }, },
    }, },

    -- when hashing on cookies, hash_fallback is ignored
    { conditional = {
      if_field = "hash_on", if_match = { match = "^cookie$" },
      then_field = "hash_fallback", then_match = { one_of = { "none" }, },
    }, },

    -- hash_fallback must not equal hash_on (headers are allowed)
    { conditional = {
      if_field = "hash_on", if_match = { match = "^consumer$" },
      then_field = "hash_fallback", then_match = { one_of = { "none", "ip", "header", "cookie" }, },
    }, },
    { conditional = {
      if_field = "hash_on", if_match = { match = "^ip$" },
      then_field = "hash_fallback", then_match = { one_of = { "none", "consumer", "header", "cookie" }, },
    }, },

    -- different headers
    { distinct = { "hash_on_header", "hash_fallback_header" }, },
  },

  -- This is a hack to preserve backwards compatibility with regard to the
  -- behavior of the hash_on field, and have it take place both in the Admin API
  -- and via declarative configuration.
  shorthand_fields = {
    { algorithm = {
      type = "string",
      func = function(value)
        if value == "least-connections" then
          return {
            algorithm = value,
            hash_on = null,
          }
        else
          return {
            algorithm = value,
          }
        end
      end,
    }, },
    -- Then, if hash_on is set to some non-null value, adjust the algorithm
    -- field accordingly.
    { hash_on = {
      type = "string",
      func = function(value)
        if value == null then
          return {
            hash_on = "none"
          }
        elseif value == "none" then
          return {
            hash_on = value,
            algorithm = "round-robin",
          }
        else
          return {
            hash_on = value,
            algorithm = "consistent-hashing",
          }
        end
      end
    }, },
  },
}

return r
