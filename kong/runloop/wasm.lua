local _M = {}

---@module 'resty.http.proxy_wasm'
local proxy_wasm

local kong = _G.kong
local fmt = string.format
local ngx = ngx
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local WARN = ngx.WARN

local ENABLED = false

---@type table<kong.db.schema.entities.wasm_filter_chain, ffi.cdata*|false>
local C_OPS_CACHE = {}


---@param chain kong.db.schema.entities.wasm_filter_chain
---@param skip_disabled? boolean
local function init_chain(chain, skip_disabled)
  local filters
  local n = #chain.filters

  if skip_disabled then
    n = 0
    filters = {}

    for _, filter in ipairs(chain.filters) do
      if filter.enabled then
        n = n + 1
        filters[n] = filter
      end
    end
  else
    filters = chain.filters
  end

  if n > 0 then
    local c_ops, err = proxy_wasm.new(filters)
    if not c_ops then
      error("failed instantiating filter chain: " .. tostring(err))
    end

    local ok
    ok, err = proxy_wasm.load(c_ops)
    if not ok then
      error("failed loading filters: " .. tostring(err))
    end

    C_OPS_CACHE[chain] = c_ops

  else
    C_OPS_CACHE[chain] = false
  end
end


---@return kong.db.schema.entities.wasm_filter_chain? chain
local function load_filter_chain(dao, cache_key)
  local chain, err = dao:select_by_cache_key(cache_key)

  if err then
    error(err)
  end

  if chain and chain.enabled then
    init_chain(chain, true)
    return chain
  end
end


---@param cache   table # kong.cache global instance
---@param dao     table # kong.db.wasm_filter_chains instance
---@param typ     kong.db.schema.entities.wasm_filter_chain.type
---@param entity? { id: string }
---@return kong.db.schema.entities.wasm_filter_chain? chain
local function fetch_filter_chain(cache, dao, typ, entity)
  local cache_key = dao:cache_key_for(typ, entity)

  local chain, err = cache:get(cache_key, nil,
                               load_filter_chain, dao, cache_key)

  if err then
    error(err)
  end

  return chain
end


---@param cache     table # kong.cache global instance
---@param dao       table # kong.db.wasm_filter_chains instance
---@param route?    { id: string }
---@param service?  { id: string }
---@return kong.db.schema.entities.wasm_filter_chain? chain
local function get_request_filter_chain(cache, dao, route, service)
  return route and fetch_filter_chain(cache, dao, dao.TYPES.route, route)
    or service and fetch_filter_chain(cache, dao, dao.TYPES.service, service)
                or fetch_filter_chain(cache, dao, dao.TYPES.global, dao.GLOBAL_ID)
end


---@param kong_config table
function _M.init(kong_config)
  if not kong_config.wasm then
    return
  end

  local modules = kong_config.wasm_modules_parsed
  if not modules or #modules == 0 then
    return
  end

  proxy_wasm = require "resty.http.proxy_wasm"
  ENABLED = true
end


function _M.init_worker()
  if not ENABLED then
    return true
  end

  for chain, err in kong.db.wasm_filter_chains:each() do
    if err then
      return nil, "failed initial filter chain setup: " .. tostring(err)
    end

    init_chain(chain)
  end

  return true
end


function _M.crud_handler(data)
  kong.worker_events.post("wasm", "crud", {
    entity = data.entity,
    operation = data.operation,
    old_entity = data.old_entity,
  })
end


---@param ctx table # the request ngx.ctx table
function _M.attach_filter_chains(ctx)
  if not ENABLED then
    return
  end

  local chain = get_request_filter_chain(kong.cache,
                                         kong.db.wasm_filter_chains,
                                         ctx.route,
                                         ctx.service)
  if not chain then
    log(DEBUG, "no filter chain enabled for request")
    return
  end

  local c_ops = C_OPS_CACHE[chain]

  if c_ops == false then
    log(DEBUG, "chain ", chain.id, " has no enabled filters")
    return

  elseif not c_ops then
    init_chain(chain, true)
    c_ops = C_OPS_CACHE[chain]

    if not c_ops then
      log(WARN, "chain ", chain.id, " has no filters")
      return
    end
  end

  local ok, err = proxy_wasm.attach(c_ops)
  if not ok then
    local msg = fmt("failed attaching filter chain %s to request: %s",
                    chain.id, err)
    log(ERR, msg)
    error(msg)
  end
end


return _M
