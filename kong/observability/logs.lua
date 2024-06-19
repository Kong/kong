local _M = {
  maybe_push = function() end,
  get_request_logs = function() return {} end,
  get_worker_logs = function() return {} end,
}

if ngx.config.subsystem ~= "http" then
  return _M
end


local request_id_get = require "kong.observability.tracing.request_id".get
local time_ns = require "kong.tools.time".time_ns
local deep_copy = require "kong.tools.utils".deep_copy

local get_log_level = require "resty.kong.log".get_log_level
local constants_log_levels = require "kong.constants".LOG_LEVELS

local table_new = require "table.new"
local string_buffer = require "string.buffer"

local ngx = ngx
local kong = kong
local table = table
local tostring = tostring
local native_ngx_log = _G.native_ngx_log or ngx.log

local ngx_null = ngx.null
local table_pack = table.pack -- luacheck: ignore

local MAX_WORKER_LOGS = 1000
local MAX_REQUEST_LOGS = 1000
local INITIAL_SIZE_WORKER_LOGS = 100
local NGX_CTX_REQUEST_LOGS_KEY = "o11y_logs_request_scoped"

local worker_logs = table_new(INITIAL_SIZE_WORKER_LOGS, 0)
local logline_buf = string_buffer.new()


-- WARNING: avoid using `ngx.log` in this function to prevent recursive loops
local function configured_log_level()
  local ok, level = pcall(get_log_level)
  if not ok then
    -- This is unexpected outside of the context of unit tests
    local level_str = kong.configuration.log_level
    native_ngx_log(ngx.WARN,
      "[observability] OpenTelemetry logs failed reading dynamic log level. " ..
      "Using log level: " .. level_str .. " from configuration."
    )
    level = constants_log_levels[level_str]
  end

  return level
end


-- needed because table.concat doesn't like booleans
local function concat_tostring(tab)
  local tab_len = #tab
  if tab_len == 0 then
    return ""
  end

  for i = 1, tab_len do
    local value = tab[i]

    if value == ngx_null then
      value = "nil"
    else
      value = tostring(value)
    end

    logline_buf:put(value)
  end

  return logline_buf:get()
end


local function generate_log_entry(request_scoped, log_level, log_str, request_id, debug_info)

  local span_id

  if request_scoped then
    -- add tracing information if tracing is enabled
    local active_span = kong and kong.tracing and kong.tracing.active_span()
    if active_span then
      span_id = active_span.span_id
    end
  end

  local attributes = {
    ["request.id"] = request_id,
    ["introspection.current.line"] = debug_info.currentline,
    ["introspection.name"] = debug_info.name,
    ["introspection.namewhat"] = debug_info.namewhat,
    ["introspection.source"] = debug_info.source,
    ["introspection.what"] = debug_info.what,
  }

  local now_ns = time_ns()
  return {
    time_unix_nano = now_ns,
    observed_time_unix_nano = now_ns,
    log_level = log_level,
    body = log_str,
    attributes = attributes,
    span_id = span_id,
  }
end


local function get_request_log_buffer()
  local log_buffer = ngx.ctx[NGX_CTX_REQUEST_LOGS_KEY]
  if not log_buffer then
    log_buffer = table_new(10, 0)
    ngx.ctx[NGX_CTX_REQUEST_LOGS_KEY] = log_buffer
  end
  return log_buffer
end


function _M.maybe_push(stack_level, log_level, ...)
  -- WARNING: do not yield in this function, as it is called from ngx.log

  -- Early return cases:

  -- log level too low
  if configured_log_level() < log_level then
    return
  end

  local log_buffer, max_logs
  local request_id = request_id_get()
  local request_scoped = request_id ~= nil

  -- get the appropriate log buffer depending on the current context
  if request_scoped then
    log_buffer = get_request_log_buffer()
    max_logs = MAX_REQUEST_LOGS

  else
    log_buffer = worker_logs
    max_logs = MAX_WORKER_LOGS
  end

  -- return if log buffer is full
  if #log_buffer >= max_logs then
    native_ngx_log(ngx.NOTICE,
      "[observability] OpenTelemetry logs buffer is full: dropping log entry."
    )
    return
  end

  -- no (or empty) log line
  local args = table_pack(...)
  local log_str = concat_tostring(args)
  if log_str == "" then
    return
  end

  -- generate & push log entry
  local debug_info = debug.getinfo(stack_level, "nSl")
  local log_entry = generate_log_entry(request_scoped, log_level, log_str, request_id, debug_info)
  table.insert(log_buffer, log_entry)
end


function _M.get_worker_logs()
  local wl = worker_logs
  worker_logs = table_new(INITIAL_SIZE_WORKER_LOGS, 0)
  return wl
end


function _M.get_request_logs()
  local request_logs = get_request_log_buffer()
  return deep_copy(request_logs)
end


return _M
