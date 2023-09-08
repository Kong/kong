local to_hex = require "resty.string".to_hex
local base = require "resty.core.base"

local get_request = base.get_request


-- Request ID types
-- higher value means higher priority
-- CORR  = correlation ID
-- TRACE = trace ID
-- INIT  = the initial value
local TYPES = {
  INIT = {
    name = "initial",
    priority = 1,
  },
  TRACE = {
    name = "trace",
    priority = 2,
  },
  CORR = {
    name = "correlation",
    priority = 3,
  },
}

local NGX_VAR_PHASES = {
  set           = true,
  rewrite       = true,
  access        = true,
  content       = true,
  header_filter = true,
  body_filter   = true,
  log           = true,
  balancer      = true,
}


local function get_ctx_request_id()
  return ngx.ctx.request_id
end


local function set_ctx_request_id(id, type)
  ngx.ctx.request_id = {
    id = id,
    type = type,
  }
end


--- Function `should_overwrite_id` determines whether the new request id
-- should overwrite the current one.
--
-- This function uses the provided (new) request id type to compare it with the
-- current (old) request id's and determine whether the new has more priority
-- than the old and should overwrite it.
--
-- @function should_overwrite_id
-- @param new_type The new request id's type
-- @param old_type The old request id's type
-- @return boolean whether the new request id should overwrite the current one
local function should_overwrite_id(new_type, old_type)
  if new_type.priority < old_type.priority then
    kong.log.info("request_id of type: ", new_type.name,
                  "is less prioritary than current type: ", old_type.name)
    return false
  end

  return true
end


local function get()
  if not get_request() then
    return nil, "no request found"
  end

  local rid = get_ctx_request_id()
  rid = rid and rid.id

  if not rid then
    -- first access to the request id for this request:
    -- try to initialize with the value of $kong_request_id
    local ok
    ok, rid = pcall(function() return ngx.var.kong_request_id end)

    if ok and rid then
      set_ctx_request_id(rid, TYPES.INIT)
    end
  end

  return rid
end


local function set(id, type)
  -- phase and input checks
  local phase = ngx.get_phase()
  assert(NGX_VAR_PHASES[phase], "cannot set request_id in '" .. phase .. "' phase")
  if not id or not type then
    return nil, "both id and type are required"
  end

  -- priority check
  local old_type = ngx.ctx.request_id and ngx.ctx.request_id.type or TYPES.INIT
  if not should_overwrite_id(type, old_type) then
    return nil, "priority check failed for request_id: " .. id .. " (" .. type.name .. ")"
  end

  -- the following line produces an error log that includes the current
  -- request_id, so both the old and new IDs are visible in the output
  kong.log.notice("setting request_id to: '", id, "' (", type.name ,
                  ") for the current request")

  set_ctx_request_id(id, type)
  ngx.var.kong_request_id = id
end


-- rewrite handler: updates request_id with trace_id, if available
local function rewrite()
  assert(ngx.get_phase() == "rewrite", "must be called from rewrite phase")

  local root_span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  local trace_id = root_span and root_span.trace_id

  if trace_id then
    set(to_hex(trace_id), TYPES.TRACE)
  end
end


return {
  get     = get,
  set     = set,
  TYPES   = TYPES,
  rewrite = rewrite,

  -- for unit testing
  _should_overwrite_id = should_overwrite_id,
  _get_ctx_request_id  = get_ctx_request_id,
  _set_ctx_request_id  = set_ctx_request_id,
}
