local _M = {}

local enabled = false

---@module 'resty.http.proxy_wasm'
local proxy_wasm

local NONE = { id = -1 }


local function extend(t, extra)
  local n = #t

  for i = 1, #extra do
    t[n + i] = extra[i]
  end
end



function _M.init(kong_config)
  if not kong_config.wasm then
    return
  end

  local filters = kong_config.wasm_modules_parsed
  if not filters or #filters == 0 then
    return
  end

  enabled = true
  proxy_wasm = require "resty.http.proxy_wasm"
end


function _M.attach_filter_chains(ctx)
  if not enabled then
    return
  end

  local service = ctx.service or NONE
  local route = ctx.route or NONE

  local filters = {}

  for chain, err in kong.db.wasm_filter_chains:each() do
    if err then
      error(err)
    end

    local service_id = chain.service and chain.service.id
    local route_id = chain.route and chain.route.id

    -- global filter chains first
    if not service_id and not route_id then
      extend(filters, chain.filters)

    -- service filter chains
    elseif service_id and not route_id then
      if service_id == service.id then
        extend(filters, chain.filters)
      end

    -- route filter chains
    elseif route_id and not service_id then
      if route_id == route.id then
        extend(filters, chain.filters)
      end

    -- route + service filter chains
    elseif service_id and route_id then
      if route_id == route.id and service_id == service.id then
        extend(filters, chain.filters)
      end
    end
  end

  if #filters == 0 then
    return
  end

  ngx.log(ngx.DEBUG, "attaching ", #filters, " wasm filters to request")

  local c_ops, err = proxy_wasm.new(filters)
  if not c_ops then
    error(err)
  end

  local ok
  ok, err = proxy_wasm.load(c_ops)
  if not ok then
    error(err)
  end

  ok, err = proxy_wasm.attach(c_ops)
  if not ok then
    error(err)
  end
end


return _M
