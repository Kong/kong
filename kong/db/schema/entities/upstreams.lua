local Schema = require "kong.db.schema"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"


local validate_name = function(name)
  local p = utils.normalize_ip(name)
  if not p then
    return nil, "Invalid name; must be a valid hostname"
  end
  if p.type ~= "name" then
    return nil, "Invalid name; no ip addresses allowed"
  end
  if p.port then
    return nil, "Invalid name; no port allowed"
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


local positive_int_or_zero = Schema.define {
  type = "integer",
  between = { 0, 2 ^ 31 },
}


local check_type = Schema.define {
  type = "string",
  one_of = { "tcp", "http", "https" },
  default = "http",
}


local check_verify_certificate = Schema.define {
  type = "boolean",
  default = true,
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
  successes = positive_int_or_zero,
  tcp_failures = positive_int_or_zero,
  timeouts = positive_int_or_zero,
  http_failures = positive_int_or_zero,
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


local r =  {
  name = "upstreams",
  primary_key = { "id" },
  endpoint_key = "name",
  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { name = { type = "string", required = true, unique = true, custom_validator = validate_name }, },
    { algorithm = { type = "string", default = "consistent", one_of = { "consistent", "least" }, }, },
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

    -- if algorithm is "least" then hash_on must be "none"
    { conditional = {
      if_field = "algorithm", if_match = { match = "^least$" },
      then_field = "hash_on", then_match = { eq = "none" },
    }, },
  },
}

return r
