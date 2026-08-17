local ngx = ngx
local var = ngx.var
local get_phase = ngx.get_phase


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
  local rid = get_ctx_request_id()

  if not rid then
    local phase = get_phase()
    if not NGX_VAR_PHASES[phase] then
      return nil, "cannot access ngx.var in " .. phase .. " phase"
    end

    -- first access to the request id for this request:
    -- initialize with the value of $kong_request_id
    rid = var.kong_request_id
    ngx.ctx.request_id = rid
  end

  return rid
end


return {
  get = get,

  -- for unit testing
  _get_ctx_request_id = get_ctx_request_id,
}
