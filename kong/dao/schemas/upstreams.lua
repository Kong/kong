local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local match = string.match
local sub = string.sub

local DEFAULT_SLOTS = 10000
local SLOTS_MIN, SLOTS_MAX = 10, 2^16
local SLOTS_MSG = "number of slots must be between " .. SLOTS_MIN .. " and " .. SLOTS_MAX


local function check_seconds(arg)
  if arg < 0 or arg > 65535 then
    return false, "must be between 0 and 65535"
  end
end


local function check_positive_int(t)
  if t < 1 or t > 2^31 - 1 or math.floor(t) ~= t then
    return false, "must be an integer between 1 and " .. 2^31 - 1
  end

  return true
end


local function check_positive_int_or_zero(t)
  if t == 0 then
    return true
  end

  local ok = check_positive_int(t)
  if not ok then
    return false, "must be 0 (disabled), or an integer between 1 and "
                  .. 2 ^31 - 1
  end

  return true
end


local function check_http_path(arg)
  if match(arg, "^%s*$") then
    return false, "path is empty"
  end
  if sub(arg, 1, 1) ~= "/" then
    return false, "must be prefixed with slash"
  end
  return true
end


local function check_http_statuses(arg)
  for _, s in ipairs(arg) do
    if type(s) ~= "number" then
      return false, "array element is not a number"
    end

    if math.floor(s) ~= s then
      return false, "must be an integer"
    end

    -- Accept any three-digit status code,
    -- applying Postel's law in case of nonstandard HTTP codes
    if s < 100 or s > 999 then
      return false, "invalid status code '" .. s ..
                    "': must be between 100 and 999"
    end
  end
  return true
end


-- same fields as lua-resty-healthcheck library
local healthchecks_defaults = {
  active = {
    timeout = 1,
    concurrency = 10,
    http_path = "/",
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


local funcs = {
  timeout = check_seconds,
  concurrency = check_positive_int,
  interval = check_seconds,
  successes = check_positive_int_or_zero,
  tcp_failures = check_positive_int_or_zero,
  timeouts = check_positive_int_or_zero,
  http_failures = check_positive_int_or_zero,
  http_path = check_http_path,
  http_statuses = check_http_statuses,
}


local function gen_schema(tbl)
  local ret = {}
  for k, v in pairs(tbl) do
    if type(v) == "number" or type(v) == "string" then
      ret[k] = { type = type(v), default = v, func = funcs[k] }

    elseif type(v) == "table" then
      if v[1] then
        ret[k] = { type = "array", default = v, func = funcs[k] }
      else
        ret[k] = { type = "table", schema = gen_schema(v), default = v }
      end
    end
  end
  return { fields = ret }
end


return {
  table = "upstreams",
  primary_key = {"id"},
  fields = {
    id = {
      type = "id",
      dao_insert_value = true,
      required = true,
    },
    created_at = {
      type = "timestamp",
      immutable = true,
      dao_insert_value = true,
      required = true,
    },
    name = {
      -- name is a hostname like name that can be referenced in an `upstream_url` field
      type = "string",
      unique = true,
      required = true,
    },
    hash_on = {
      -- primary hash-key
      type = "string",
      default = "none",
      enum = {
        "none",
        "consumer",
        "ip",
        "header",
        "cookie",
      },
    },
    hash_fallback = {
      -- secondary key, if primary fails
      type = "string",
      default = "none",
      enum = {
        "none",
        "consumer",
        "ip",
        "header",
        "cookie",
      },
    },
    hash_on_header = {
      -- header name, if `hash_on == "header"`
      type = "string",
    },
    hash_fallback_header = {
      -- header name, if `hash_fallback == "header"`
      type = "string",
    },
    hash_on_cookie = {
      -- cookie name, if `hash_on` or `hash_fallback` == `"cookie"`
      type = "string",
    },
    hash_on_cookie_path = {
      -- cookie path, if `hash_on` or `hash_fallback` == `"cookie"`
      type = "string",
      default = "/",
    },
    slots = {
      -- the number of slots in the loadbalancer algorithm
      type = "number",
      default = DEFAULT_SLOTS,
    },
    healthchecks = {
      type = "table",
      schema = gen_schema(healthchecks_defaults),
      default = healthchecks_defaults,
    },
  },
  self_check = function(schema, config, dao, is_updating)

    -- check the name
    if config.name then
      local p = utils.normalize_ip(config.name)
      if not p then
        return false, Errors.schema("Invalid name; must be a valid hostname")
      end
      if p.type ~= "name" then
        return false, Errors.schema("Invalid name; no ip addresses allowed")
      end
      if p.port then
        return false, Errors.schema("Invalid name; no port allowed")
      end
    end

    if config.hash_on_header then
      local ok, err = utils.validate_header_name(config.hash_on_header)
      if not ok then
        return false, Errors.schema("Header: " .. err)
      end
    end

    if config.hash_fallback_header then
      local ok, err = utils.validate_header_name(config.hash_fallback_header)
      if not ok then
        return false, Errors.schema("Header: " .. err)
      end
    end

    if config.hash_on_cookie then
      local ok, err = utils.validate_cookie_name(config.hash_on_cookie)
      if not ok then
        return false, Errors.schema("Cookie name: " .. err)
      end
    end

    if config.hash_on_cookie_path then
      local ok, err = check_http_path(config.hash_on_cookie_path)
      if not ok then
        return false, Errors.schema("Cookie path: " .. err)
      end
    end

    if (config.hash_on == "header"
        and not config.hash_on_header) or
       (config.hash_fallback == "header"
        and not config.hash_fallback_header) then
      return false, Errors.schema("Hashing on 'header', " ..
                                  "but no header name provided")
    end

    if (config.hash_on == "cookie" or config.hash_fallback == "cookie")
        and not config.hash_on_cookie then
      return false, Errors.schema("Hashing on 'cookie', " ..
                                  "but no cookie name provided")
    end

    if config.hash_on and config.hash_fallback then
      if config.hash_on == "none" then
        if config.hash_fallback ~= "none" then
          return false, Errors.schema("Cannot set fallback if primary " ..
                                      "'hash_on' is not set")
        end

      elseif config.hash_on == "cookie" then
        if config.hash_fallback ~= "none" then
          -- Cookie value will be set with the server response if not present,
          -- so the fallback value would never be evaluated.
          return false, Errors.schema("Cannot set `hash_fallback` if primary " ..
                                      "`hash_on` is set to cookie")
        end

      else
        if config.hash_on == config.hash_fallback then
          if config.hash_on ~= "header" then
            return false, Errors.schema("Cannot set fallback and primary " ..
                                        "hashes to the same value")

          else
            local upper_hash_on = config.hash_on_header:upper()
            local upper_hash_fallback = config.hash_fallback_header:upper()
            if upper_hash_on == upper_hash_fallback then
              return false, Errors.schema("Cannot set fallback and primary "..
                                          "hashes to the same value")
            end
          end
        end
      end
    end

    if config.slots then
      -- check the slots number
      if config.slots < SLOTS_MIN or config.slots > SLOTS_MAX then
        return false, Errors.schema(SLOTS_MSG)
      end
    end

    return true
  end,
}
