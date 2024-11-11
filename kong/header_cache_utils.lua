local str_replace_char = require("resty.core.utils").str_replace_char
local CACHE_HEADERS = require("kong.constants").CACHE_HEADERS

local function clear_headers_cache()
  ngx.ctx[CACHE_HEADERS[1].KEY] = nil
  ngx.ctx[CACHE_HEADERS[2].KEY] = nil
  ngx.ctx[CACHE_HEADERS[1].FLAG] = nil
  ngx.ctx[CACHE_HEADERS[2].FLAG] = nil
end

local function init_headers_cache(group)
  ngx.ctx[CACHE_HEADERS[group].KEY] = {}
  return true
end

local function normalize_header_name(header)
    return str_replace_char(header:lower(), "-", "_")
end

local function normalize_header_value(value)
  local tvalue = type(value)

  if tvalue == "table" then
    for i, v in ipairs(value) do
      value[i] = normalize_header_value(v)
    end
    return value
  elseif value == nil or (value == "") then
    return nil
  elseif tvalue == "string" then
    return value
  end

  -- header is number or boolean
  return tostring(value)
end


local function builtin_header_single_handler(cache, key, value)
  key = normalize_header_name(key)
  if type(value) == "table" then
    if (#value == 0) then
      cache[key] = nil
    else
      cache[key] = normalize_header_value(value[#value])
    end
  else
      cache[key] = normalize_header_value(value)
  end
end

local function multi_value_handler(cache, key, value, override)
  key = normalize_header_name(key)

  -- if add_header with empty string (override == nil and value == ""), special handling to keep consistency
  if (override or value ~= "") then
    value = normalize_header_value(value)
  end

  if override then
    -- override mode, assign directly
    cache[key] = value
  else
    if not cache[key] then
    -- if cache key not exists, assign directly
      cache[key]  = value
      return
    end

    -- field exists for adding, change single value to list
    if type(ngx.ctx.cache_headers[key]) ~= "table" then
        cache[key] = { cache[key] }
    end

    -- values insert
    if type(value) == "table" then
        for i, v in ipairs(value) do
            table.insert(cache[key], v)
        end
    else
        table.insert(cache[key], value)
    end
  end
end

local function set_header_cache(group, name, value, override)
  local cache = ngx.ctx[CACHE_HEADERS[group].KEY] or init_headers_cache(group) and ngx.ctx[CACHE_HEADERS[group].KEY]

  if CACHE_HEADERS[group].SINGLE_VALUES[name] then
    builtin_header_single_handler(cache, name, value)
  else
    multi_value_handler(cache, name, value, override)
  end
end

local function add_header_cache(group, name, value)
  local cache = ngx.ctx[CACHE_HEADERS[group].KEY] or init_headers_cache(group) and ngx.ctx[CACHE_HEADERS[group].KEY]

  if CACHE_HEADERS[group].SINGLE_VALUES[name] then
    builtin_header_single_handler(cache, name, value)
  else
    multi_value_handler(cache, name, value)
  end
end

-- set cache headers by group[request/response]
local function set_headers_cache(group, values)
  -- if no key specified, assign the whole cache group value
  local cache_key = CACHE_HEADERS[group].KEY
  local cache_flag = CACHE_HEADERS[group].FLAG
  ngx.ctx[cache_key] = values
  if not ngx.ctx[cache_flag] then
      ngx.ctx[cache_flag] = true
  end
end

-- get cache headers by group[request/response]
local function get_headers_cache(group)
  -- if headers has not been fully got before, return nil
  return ngx.ctx[CACHE_HEADERS[group].FLAG] and ngx.ctx[CACHE_HEADERS[group].KEY]
end

-- get cache header
local function get_header_cache(group, key)
  local fields = ngx.ctx[group]
  if fields then
      return ngx.ctx[group][key]
  end
  return fields
end

return {
  set_header_cache = set_header_cache,
  add_header_cache = add_header_cache,
  set_headers_cache = set_headers_cache,
  get_headers_cache = get_headers_cache,
  get_header_cache = get_header_cache,
  clear_headers_cache = clear_headers_cache,
}