local base = require "resty.core.base"

local get_request = base.get_request

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


local function get()
  if not get_request() then
    return nil, "no request found"
  end

  local rid = get_ctx_request_id()

  if not rid then
    local phase = ngx.get_phase()
    if not NGX_VAR_PHASES[phase] then
      return nil, "cannot access ngx.var in " .. phase .. " phase"
    end

    -- first access to the request id for this request:
    -- initialize with the value of $kong_request_id
    rid = ngx.var.kong_request_id
    ngx.ctx.request_id = rid
  end

  return rid
end


return {
  get = get,

  -- for unit testing
  _get_ctx_request_id = get_ctx_request_id,
}
