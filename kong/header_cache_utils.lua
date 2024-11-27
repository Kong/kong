local str_replace_char = require("resty.core.utils").str_replace_char
local CACHE_HEADERS = require("kong.constants").CACHE_HEADERS
local clone = require "table.clone"

-- make header name in cache table lowercase without replacing '-' to '_'.
local function normalize_header_name(header)
  return header:lower()
end

-- clear headers cache table
-- @param `group` 1 for request, 2 for response
local function clear_header_cache_proxy(group)
  ngx.ctx[CACHE_HEADERS[group].KEY] = nil
end

-- set cache table to stale(stale cache need to be refreshed)
local function set_stale(group)
  ngx.ctx[CACHE_HEADERS[group].FLAG] = nil
end

-- this is the same __index logic as `ngx_http_lua_create_headers_metatable`
-- in lua-nginx-module, so that the indexing of table behaves like the table
-- return from ngx.req(resp).get_headers function.
local lower_fetch = function(tbl, key)
  local new_key = string.gsub(string.lower(key), '_', '-')
  if new_key ~= key then 
    return tbl[new_key] 
  else 
    return nil
  end
end

local mt = {
  __index = lower_fetch
}

-- get headers cache table in ngx.ctx.
-- @param `group` 1 for request, 2 for response
-- @return nil if the cache is not initialized or stale 
local function get_headers_cache_internal(group)
  local cache_key = CACHE_HEADERS[group].KEY
  local cache_flag = CACHE_HEADERS[group].FLAG
  if ngx.ctx[cache_key] and ngx.ctx[cache_flag] then
    return ngx.ctx[cache_key]
  end
  return nil
end

-- set cache headers in ngx.ctx
-- @param `group` 1 for request, 2 for response
-- @param `values` the headers table got from resty get_headers API
local function set_headers_cache(group, values)
  local cache_key = CACHE_HEADERS[group].KEY
  local cache_flag = CACHE_HEADERS[group].FLAG
  clear_header_cache_proxy(group)
  ngx.ctx[cache_key] = values
  -- mark cache fresh
  ngx.ctx[cache_flag] = true
end

-- set a single header cache in ngx.ctx, not entire cache table
-- @param `group` 1 for request, 2 for response
-- @param `name` header name
-- @param `value` the header value got from ngx.header.HEADER
local function set_single_header_cache(group, name, value)
  local cache_key = CACHE_HEADERS[group].KEY
  -- in case cache table not yet initialized
  if ngx.ctx[cache_key] == nil then
    ngx.ctx[cache_key] = {}
  end
  ngx.ctx[cache_key][normalize_header_name(name)] = value
end

-- get header value from cache in ngx.ctx
-- @param `group` 1 for request, 2 for response
-- @param `name` header name
-- @return the value of a header as the same format as `get_headers()[name]`
local function get_header_cache(group, name)
  local cache_key = CACHE_HEADERS[group].KEY
  if ngx.ctx[cache_key] then
    local value = ngx.ctx[cache_key][normalize_header_name(name)]
    if value == nil then
      return nil
    end
    if type(value) ~= "table" then
      return value
    else
      -- clone the table, to avoid temp change in result table applying to cache
      return clone(value)
    end
  end
  return nil
end

-- clear all headers cache in ngx.ctx
local function clear_headers_cache()
  clear_header_cache_proxy(1)
  clear_header_cache_proxy(2)
  set_stale(1)
  set_stale(2)
end

-- set stale flag on single header cache, mark it stale.
-- single cache set to `nil` and flag set to stale. so that for single header
-- get we only update the single cache, for get_headers, we update whole cache.
-- @param `group` 1 for request, 2 for response
-- @param `name` header name
local function set_cache_stale(group, name)
  local cache = get_headers_cache_internal(group)
  if cache then
    cache[normalize_header_name(name)] = nil
    set_stale(group)
  end
end

-- duplicate a headers table from cache with same indexing logic.
-- we need a clone to avoid temp change in result table applying to cache
-- @param `group` 1 for request, 2 for response
-- @return the value of a header as the same format as `get_headers()[name]`
local function duplicate_headers_cache(group)
  local new_headers = clone(get_headers_cache_internal(group))
  -- add metatable for __index method, because clone will lose the metatable
  setmetatable(new_headers, mt)
  return new_headers
end


-- get headers cache table in ngx.ctx.
-- @param `group` 1 for request, 2 for response
-- @return nil if the cache is not initialized or stale
local function get_headers_cache(group)
  if get_headers_cache_internal(group) ~= nil then
    return duplicate_headers_cache(group)
  end
  return nil
end

return {
  set_headers_cache = set_headers_cache,
  get_headers_cache = get_headers_cache,
  get_header_cache = get_header_cache,
  clear_headers_cache = clear_headers_cache,
  set_cache_stale = set_cache_stale,
  set_single_header_cache = set_single_header_cache,
}
