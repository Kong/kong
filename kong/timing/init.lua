local context             = require("kong.timing.context")
local cjson               = require("cjson.safe")
local req_dyn_hook        = require("kong.dynamic_hook")
local constants           = require("kong.constants")

local ngx                 = ngx
local ngx_var             = ngx.var
local ngx_req_set_header  = ngx.req.set_header

local string_format       = string.format

local request_id_get      = require("kong.tracing.request_id").get

local FILTER_ALL_PHASES = {
  ssl_cert      = nil,    -- NYI
                          -- in this phase, we can't get request headers
                          -- as we are in the layer 4,
                          -- so we can't know whether to trace or not.
  rewrite       = true,
  balancer      = true,
  access        = true,
  header_filter = true,
  body_filter   = true,
  log           = true,
  upstream      = true,
}

--[[
  We should truncate the large output in response header
  as some downstream (like nginx) may not accept large header.
  (e.g. nginx default limit is 4k|8k based on the plateform)

  We should split the large output in error_log
  as OpenResty will truncate the log message that is larger than 4k.
--]]
local HEADER_JSON_TRUNCATE_LENGTH = 1024 * 2 -- 2KBytes
local LOG_JSON_TRUNCATE_LENGTH    = 1024 * 3 -- 3KBytes

local enabled = false

local _M = {}


local function should_run()
  return ngx.ctx.req_trace_ctx:should_run()
end


local function is_loopback(binary_addr)
  -- ipv4 127.0.0.0/8 or ipv6 ::1
  if (#binary_addr == 4 and binary_addr:byte(1) == 127) or
     binary_addr == "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"
  then
    return true
  end

  return false
end

function _M.auth()
  if not enabled then
    return
  end

  assert(ngx.ctx.req_trace_id == nil)

  local http_x_kong_request_debug = ngx_var.http_x_kong_request_debug
  local http_x_kong_request_debug_token = ngx_var.http_x_kong_request_debug_token
  local http_x_kong_request_debug_log = ngx_var.http_x_kong_request_debug_log

  if http_x_kong_request_debug then
    ngx_req_set_header("X-Kong-Request-Debug", nil)
  end

  if http_x_kong_request_debug_token then
    ngx_req_set_header("X-Kong-Request-Debug-Token", nil)
  end

  if http_x_kong_request_debug_log then
    ngx_req_set_header("X-Kong-Request-Debug-Log", nil)
  end

  if http_x_kong_request_debug == nil or
     http_x_kong_request_debug ~= "*"
  then
    -- fast path for no filter
    return
  end

  local loopback = is_loopback(ngx_var.binary_remote_addr)

  if not loopback then
    if http_x_kong_request_debug_token ~= kong.request_debug_token then
      return
    end
  end

  local ctx = context.new(FILTER_ALL_PHASES, {
    log = http_x_kong_request_debug_log == "true",
    loopback = loopback,
  })
  ctx:set_context_prop("request_id", request_id_get())
  ngx.ctx.req_trace_ctx = ctx
  req_dyn_hook.enable_on_this_request("timing")
end


function _M.enter_context(name)
  if not should_run() then
    return
  end

  ngx.ctx.req_trace_ctx:enter_subcontext(name)
end


function _M.leave_context()
  if not should_run() then
    return
  end

  ngx.ctx.req_trace_ctx:leave_subcontext()
end


function _M.set_context_prop(k, v)
  if not should_run() then
    return
  end

  ngx.ctx.req_trace_ctx:set_context_prop(k, v)
end


function _M.get_context_kv(k)
  if not should_run() then
    return
  end

  return ngx.ctx.req_trace_ctx:get_context_kv(k)
end


function _M.set_root_context_prop(k, v)
  ngx.ctx.req_trace_ctx:set_root_context_prop(k, v)
end


function _M.header_filter()
  local req_tr_ctx = ngx.ctx.req_trace_ctx

  req_tr_ctx:mock_upstream_phase()
  local output = req_tr_ctx:to_json()

  if #output >= HEADER_JSON_TRUNCATE_LENGTH and not req_tr_ctx:from_loopback() then
    output = assert(cjson.encode({
      truncated = true,
      request_id = ngx.ctx.req_trace_ctx:get_root_context_kv("request_id"),
      message = "Output is truncated, please check the error_log for full output by filtering with the request_id.",
    }))

    ngx.ctx.req_trace_ctx.log = true
  end

  ngx.header["X-Kong-Request-Debug-Output"] = output
end


function _M.log()
  local req_tr_ctx = ngx.ctx.req_trace_ctx

  if not req_tr_ctx:needs_logging() then
    return
  end

  req_tr_ctx:mock_upstream_phase()
  local output = req_tr_ctx:to_json()

  if #output >= LOG_JSON_TRUNCATE_LENGTH then
    -- split the output into N parts
    local parts = {}
    local i = 1
    local j = 1
    local len = #output

    while i <= len do
      parts[j] = output:sub(i, i + LOG_JSON_TRUNCATE_LENGTH - 1)
      i = i + LOG_JSON_TRUNCATE_LENGTH
      j = j + 1
    end

    local nparts = #parts
    for no, part in ipairs(parts) do
      local msg = string_format("%s parts: %d/%d output: %s",
                                constants.REQUEST_DEBUG_LOG_PREFIX,
                                no, nparts, part)
      ngx.log(ngx.NOTICE, msg)
    end

    return
  end

  local msg = string_format("%s output: %s",
                            constants.REQUEST_DEBUG_LOG_PREFIX,
                            output)
  ngx.log(ngx.NOTICE, msg)
end


function _M.init_worker(is_enabled)
  enabled = is_enabled and ngx.config.subsystem == "http"

  if enabled then
    req_dyn_hook.always_enable("timing:auth")
  end
end


function _M.register_hooks()
  require("kong.timing.hooks").register_hooks(_M)

  req_dyn_hook.hook("timing:auth", "auth", function()
    _M.auth()
  end)

  req_dyn_hook.hook("timing", "dns:cache_lookup", function(cache_hit)
    _M.set_context_prop("cache_hit", cache_hit)
  end)

  req_dyn_hook.hook("timing", "workspace_id:got", function(id)
    _M.set_root_context_prop("workspace_id", id)
  end)

  req_dyn_hook.hook("timing", "before:rewrite", function()
    _M.enter_context("rewrite")
  end)

  req_dyn_hook.hook("timing", "after:rewrite", function()
    _M.leave_context() -- leave rewrite
  end)

  req_dyn_hook.hook("timing", "before:balancer", function()
    _M.enter_context("balancer")
  end)

  req_dyn_hook.hook("timing", "after:balancer", function()
    _M.leave_context() -- leave balancer
  end)

  req_dyn_hook.hook("timing", "before:access", function()
    _M.enter_context("access")
  end)

  req_dyn_hook.hook("timing", "after:access", function()
    _M.leave_context() -- leave access
  end)

  req_dyn_hook.hook("timing", "before:response", function()
    _M.enter_context("response")
  end)

  req_dyn_hook.hook("timing", "after:response", function()
    _M.leave_context() -- leave response
  end)

  req_dyn_hook.hook("timing", "before:header_filter", function()
    _M.enter_context("header_filter")
  end)

  req_dyn_hook.hook("timing", "after:header_filter", function()
    _M.leave_context() -- leave header_filter
    _M.header_filter()
  end)

  req_dyn_hook.hook("timing", "before:body_filter", function()
    _M.enter_context("body_filter")
  end)

  req_dyn_hook.hook("timing", "after:body_filter", function()
    _M.leave_context() -- leave body_filter
  end)

  req_dyn_hook.hook("timing", "before:log", function()
    _M.enter_context("log")
  end)

  req_dyn_hook.hook("timing", "after:log", function()
    _M.leave_context() -- leave log
    _M.log()
  end)

  req_dyn_hook.hook("timing", "before:plugin_iterator", function()
    _M.enter_context("plugins")
  end)

  req_dyn_hook.hook("timing", "after:plugin_iterator", function()
    _M.leave_context() -- leave plugins
  end)

  req_dyn_hook.hook("timing", "before:plugin", function(plugin_name, plugin_id)
    _M.enter_context(plugin_name)
    _M.enter_context(plugin_id)
  end)

  req_dyn_hook.hook("timing", "after:plugin", function()
    _M.leave_context() -- leave plugin_id
    _M.leave_context() -- leave plugin_name
  end)

  req_dyn_hook.hook("timing", "before:router", function()
    _M.enter_context("router")
  end)

  req_dyn_hook.hook("timing", "after:router", function()
    _M.leave_context() -- leave router
  end)
end


return _M
