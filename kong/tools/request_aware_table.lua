local table_clear = require "table.clear"

local LOG_LEVELS = require "kong.constants".LOG_LEVELS
local get_log_level = require("resty.kong.log").get_log_level

local get_phase = ngx.get_phase
local fmt = string.format
local ngx_var = ngx.var

local NGX_VAR_PHASES = {
  set = true,
  rewrite = true,
  balancer = true,
  access = true,
  content = true,
  header_filter = true,
  body_filter = true,
  log = true,
}


local function is_debug_mode()
  local log_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])
  return log_level == LOG_LEVELS.debug
end


--- Request aware table constructor
-- Wraps an existing table (or creates a new one) with request-aware access
-- logic to protect the underlying data from race conditions.
-- @param data_table (optional) The target table to use as underlying data
-- @return The newly created table with request-aware access
local function new(data_table)
  if data_table and type(data_table) ~= "table" then
    error("data_table must be a table", 2)
  end

  local allowed_request_id
  local proxy = {}
  local data  = data_table or {}

  -- Check if access is allowed based on the request ID
  local function enforce_sequential_access()
    local curr_phase = get_phase()
    if not NGX_VAR_PHASES[curr_phase] then
      error(fmt("cannot enforce sequential access in %s phase", curr_phase), 2)
    end

    local curr_request_id = ngx_var.request_id

    allowed_request_id = allowed_request_id or curr_request_id

    if curr_request_id ~= allowed_request_id then
      error("race condition detected; access to table forbidden", 2)
    end
  end

  --- Clear data table
  -- @tparam function fn (optional) An optional function to use instead
  -- of `table.clear` to clear the data table
  function proxy.clear(fn)
    if fn then
      fn(data)

    else
      table_clear(data)
    end

    allowed_request_id = nil
  end

  local _proxy_mt = {
    __index = function(_, k)
      if is_debug_mode() then
        enforce_sequential_access()
      end

      return data[k]
    end,

    __newindex = function(_, k, v)
      if is_debug_mode() then
        enforce_sequential_access()
      end

      data[k] = v
    end
  }

  return setmetatable(proxy, _proxy_mt)
end

return {
  new = new,
}
