--- NOTE: tool is designed to assist with **detecting** request contamination
-- issues on CI, during test runs. It does not offer security safeguards.

local table_new = require("table.new")
local table_clear = require("table.clear")
local get_request_id = require("kong.tracing.request_id").get


-- set in new()
local is_not_debug_mode


local error        = error
local rawset       = rawset
local rawget       = rawget
local setmetatable = setmetatable


local ALLOWED_REQUEST_ID_K = "__allowed_request_id"


-- Check if access is allowed for table, based on the request ID
local function enforce_sequential_access(table)
  local curr_request_id = get_request_id()

  if not curr_request_id then
    -- allow access and reset allowed request ID
    rawset(table, ALLOWED_REQUEST_ID_K, nil)
    return
  end

  local allowed_request_id = rawget(table, ALLOWED_REQUEST_ID_K)
  if not allowed_request_id then
    -- first access. Set allowed request ID and allow access
    rawset(table, ALLOWED_REQUEST_ID_K, curr_request_id)
    return
  end

  if curr_request_id ~= table[ALLOWED_REQUEST_ID_K] then
    error("concurrent access from different request to shared table detected", 2)
  end
end


local function clear_table(self)
  if is_not_debug_mode then
    table_clear(self)
    return
  end

  table_clear(self.__data)
  rawset(self, ALLOWED_REQUEST_ID_K, nil)
end


local __proxy_mt = {
  __index = function(t, k)
    if k == "clear" then
      return clear_table
    end

    enforce_sequential_access(t)
    return t.__data[k]
  end,

  __newindex = function(t, k, v)
    if k == "clear" then
      error("cannot set the 'clear' method of request aware table", 2)
    end

    enforce_sequential_access(t)
    t.__data[k] = v
  end,
}


local __direct_mt = {
  __index = { clear = clear_table },

  __newindex = function(t, k, v)
    if k == "clear" then
      error("cannot set the 'clear' method of request aware table", 2)
    end

    rawset(t, k, v)
  end,
}


-- Request aware table constructor
--
-- Creates a new table with request-aware access logic to protect the
-- underlying data from race conditions.
-- The table includes a :clear() method to delete all elements.
--
-- The request-aware access logic is turned off when `debug_mode` is disabled.
--
-- @param narr (optional) pre allocated array elements
-- @param nrec (optional) pre allocated hash elements
-- @return The newly created table with request-aware access
local function new(narr, nrec)
  local data = table_new(narr or 0, nrec or 0)

  if is_not_debug_mode == nil then
    is_not_debug_mode = (kong.configuration.log_level ~= "debug")
  end

  -- return table without proxy when debug_mode is disabled
  if is_not_debug_mode then
    return setmetatable(data, __direct_mt)
  end

  -- wrap table in proxy (for access checks) when debug_mode is enabled
  return setmetatable({ __data = data }, __proxy_mt)
end

return {
  new = new,
}
