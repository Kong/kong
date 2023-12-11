-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local sha256_hex = require "kong.tools.sha256".sha256_hex

local _M = {}

local EMPTY = {}

local function prefix_uuid(route_id)
  -- route id
  if route_id then
    return route_id
  end

  -- global default
  return "default"
end


-- Return a string with the format "key=value(:key=value)*" of the
-- actual keys and values in args that are in vary_fields.
--
-- The elements are sorted so we get consistent cache actual_keys no matter
-- the order in which params came in the request
local function generate_key_from(args, vary_fields)
  local cache_key = {}

  for _, field in pairs(vary_fields or {}) do
    local arg = args[field]
    if arg then
      if type(arg) == "table" then
        table.sort(arg)
        table.insert(cache_key, field .. "=" .. table.concat(arg, ","))

      else
        table.insert(cache_key, field .. "=" .. arg)
      end
    end
  end

  return table.concat(cache_key, ":")
end


local function query_key(body_raw)
  -- replace all multiple spaces to one space and minimize the size
  -- of the query key
  return string.gsub(body_raw, "%s+", " ")
end


-- Return the component of cache_key for vary_headers in params
--
-- If no vary_query_params are configured in the plugin, return
-- the empty string.
local function headers_key(headers, vary_headers)
  if not (vary_headers or EMPTY)[1] then
    return ""
  end

  return generate_key_from(headers, vary_headers)
end


--
-- Build cache key from query that was passed in a request body
-- @param body_raw: raw body from the request
--
function _M.build_cache_key(route_id, body_raw, headers_table, vary_headers)
  local prefix_digest = route_id and prefix_uuid(route_id) or ""
  local query_digest  = body_raw and query_key(body_raw) or ""
  local headers_digest = headers_key(headers_table, vary_headers)

  return sha256_hex(fmt("%s|%s|%s", prefix_digest, headers_digest,
                        query_digest))
end


return _M
