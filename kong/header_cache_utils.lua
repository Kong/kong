local str_replace_char = require("resty.core.utils").str_replace_char
local CACHE_HEADERS = require("kong.constants").CACHE_HEADERS

local function normalize_header_name(header)
  return header:lower()
  -- return str_replace_char(header:lower(), "-", "_")
end

local function Set (list)
  local set = {}
  for _, l in ipairs(list) do set[normalize_header_name(l)] = true end
  return set
end

do
  for k, v in pairs(CACHE_HEADERS) do
    v.SINGLE_VALUES = Set(v.SINGLE_VALUES)
  end
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

local function get_recover_cache(proxy)
  if (next(proxy.kmagic_inner) ~= nil) then
    if (next(proxy.kmagic_dirty) ~= nil) then
      for k, v in pairs(proxy.kmagic_dirty) do
        proxy.kmagic_inner[k] = v
      end
      proxy.kmagic_dirty = {}
    end
    if (next(proxy.kmagic_added)) then
      for k, _ in pairs(proxy.kmagic_added) do
        proxy.kmagic_inner[k] = nil
      end
      proxy.kmagic_added = {}
    end
  elseif next(proxy.kmagic_added) then
    -- original cache is empty, just need to clear added
    proxy.kmagic_added = {}
  end
end


local function get_headers_cache_proxy(group)
  local cache_key = CACHE_HEADERS[group].KEY
  if ngx.ctx[cache_key] then
    return ngx.ctx[cache_key]
  end
  ngx.ctx[cache_key] = {
    kmagic_dirty = {},
    kmagic_inner = {},
    kmagic_added = {},
  }
  local pxy = ngx.ctx[cache_key]
  local mt2 = {
    __index = function(_, k)
      return pxy.kmagic_inner[normalize_header_name(k)]
    end,
    __newindex = function(_, k, v)
      k = normalize_header_name(k)
      local t = pxy.kmagic_inner
      local dirty = pxy.kmagic_dirty
      local added = pxy.kmagic_added
      if dirty[k] == nil and t[k] then
        dirty[k] = t[k]
      end
      if added[k] == nil and t[k] == nil and v ~= nil then
        added[k]=true
      end
      t[k] = v
    end,
    __pairs = function()
      return next, pxy.kmagic_inner, nil
    end
  }
  setmetatable(pxy, mt2)
  return pxy
end

local function clear_header_cache_proxy(group)
  -- ngx.print("INIT\n")
  local proxy = get_headers_cache_proxy(group)
  proxy.kmagic_inner = {}
  proxy.kmagic_dirty = {}
  proxy.kmagic_added = {}
end

local function get_headers_cache(group)
  local proxy = get_headers_cache_proxy(group)
  get_recover_cache(proxy)
  return ngx.ctx[CACHE_HEADERS[group].FLAG] and proxy
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
    if type(cache[key]) ~= "table" then
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
  name = normalize_header_name(name)
  local proxy = get_headers_cache_proxy(group)
  local cache = proxy.kmagic_inner
  if (proxy.kmagic_dirty[name]) then
    proxy.kmagic_dirty[name] = nil
  elseif (proxy.kmagic_added[name]) then
    proxy.kmagic_added[name] = nil
  end
  if CACHE_HEADERS[group].SINGLE_VALUES[name] then
    builtin_header_single_handler(cache, name, value)
  else
    multi_value_handler(cache, name, value, override)
  end
end

-- set cache headers by group[request/response]
local function set_headers_cache(group, values)
  -- if no key specified, assign the whole cache group value
  -- local cache_key = CACHE_HEADERS[group].KEY
  local cache_flag = CACHE_HEADERS[group].FLAG
  -- ngx.ctx[CACHE_HEADERS[group].key] = nil
  clear_header_cache_proxy(group)
  local proxy = get_headers_cache_proxy(group)
  proxy.kmagic_inner = values
  if not ngx.ctx[cache_flag] then
      ngx.ctx[cache_flag] = true
  end
end


-- get cache header
local function get_header_cache(group, key)
  local proxy = get_headers_cache_proxy(group)
  get_recover_cache(proxy)
  return proxy[key]
end

local function clear_headers_cache()
  clear_header_cache_proxy(1)
  clear_header_cache_proxy(2)
  -- ngx.ctx[CACHE_HEADERS[1].KEY] = nil
  -- ngx.ctx[CACHE_HEADERS[2].KEY] = nil
  ngx.ctx[CACHE_HEADERS[1].FLAG] = nil
  ngx.ctx[CACHE_HEADERS[2].FLAG] = nil
end

return {
  set_header_cache = set_header_cache,
  set_headers_cache = set_headers_cache,
  get_headers_cache = get_headers_cache,
  get_header_cache = get_header_cache,
  clear_headers_cache = clear_headers_cache,
  normalize_header_name = normalize_header_name,
}
