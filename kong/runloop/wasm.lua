local _M = {}

local utils = require "kong.tools.utils"
local clear_tab = require("table.clear")

---@module 'resty.http.proxy_wasm'
local proxy_wasm

local kong = _G.kong
local ngx = ngx
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local concat = table.concat
local insert = table.insert
local sha256 = utils.sha256_bin


local VERSION_KEY = "wasm_filter_chains:version"
local TTL_ZERO = { ttl = 0 }


---
-- Fetch the current version of the filter chain state from cache
--
---@return string
local function get_version()
  return kong.core_cache:get(VERSION_KEY, TTL_ZERO, utils.uuid)
end


local TYPE_SERVICE  = 0
local TYPE_ROUTE    = 1
local TYPE_COMBINED = 2


local ENABLED = false

local hash_chain
do
  local HASH_DISABLED = sha256("disabled")
  local HASH_NONE     = sha256("none")

  local buf = {}

  ---@param chain kong.db.schema.entities.wasm_filter_chain
  ---@return string
  local function hash_chain_entity(chain)
    if not chain then
      return HASH_NONE

    elseif not chain.enabled then
      return HASH_DISABLED
    end

    local n = 0
    for _, filter in ipairs(chain.filters) do
      buf[n + 1] = filter.name
      buf[n + 2] = tostring(filter.enabled)
      buf[n + 3] = tostring(filter.enabled and sha256(filter.config))
      n = n + 3
    end

    local s = concat(buf, "", 1, n)
    clear_tab(buf)

    return sha256(s)
  end

  ---
  -- Generate a hash key for a filter chain from a route
  -- and service filter chain [entity] combo.
  --
  -- The result of this is used to invalidate cached filter chain
  -- plans.
  --
  ---@param service? kong.db.schema.entities.wasm_filter_chain
  ---@param route?   kong.db.schema.entities.wasm_filter_chain
  ---@return string
  function hash_chain(service, route)
    return sha256(hash_chain_entity(service) .. hash_chain_entity(route))
  end
end


---@class kong.runloop.wasm.filter_chain_reference
---
---@field hash   string
---@field c_plan ffi.cdata*|nil
---@field type   "service"|"route"|"combined"


---@class kong.runloop.wasm.state
local STATE = {
  ---@type table<string, kong.runloop.wasm.filter_chain_reference>
  by_service = {},

  ---@type table<string, kong.runloop.wasm.filter_chain_reference>
  by_route = {},

  ---@type table<string, table<string, kong.runloop.wasm.filter_chain_reference>>
  combined = {},

  version = -1,
}


---
-- Initialize and return a filter chain plan from a list of filters.
--
---@param filters kong.db.schema.entities.wasm_filter[]|nil
---@return ffi.cdata*? c_plan
---@return string?     error
local function init_c_plan(filters)
  if not filters then
    return
  end

  local c_plan, err = proxy_wasm.new(filters)
  if not c_plan then
    return nil, "failed instantiating filter chain: "
                .. tostring(err)
  end

  local ok
  ok, err = proxy_wasm.load(c_plan)
  if not ok then
    return nil, "failed loading filters: " .. tostring(err)
  end

  return c_plan
end


-- Helper method for retrieving a filter chain reference from
-- the state table.
--
---@param state       kong.runloop.wasm.state
---@param typ         integer
---@param service_id? string
---@param route_id?   string
---
---@return kong.runloop.wasm.filter_chain_reference? ref
local function get_chain_ref(state, typ, service_id, route_id)
  local ref

  if typ == TYPE_SERVICE and service_id then
    ref = state.by_service[service_id]

  elseif typ == TYPE_ROUTE and route_id then
    ref = state.by_route[route_id]

  elseif typ == TYPE_COMBINED and service_id and route_id then
    local routes = state.combined[service_id]
    ref = routes and routes[route_id]
  end

  return ref
end


---
-- Helper method for storing a new filter chain reference within
-- the state table.
--
---@param state       kong.runloop.wasm.state
---@param ref         kong.runloop.wasm.filter_chain_reference
---@param typ         integer
---@param service_id? string
---@param route_id?   string
local function store_chain_ref(state, ref, typ, service_id, route_id)
  if typ == TYPE_SERVICE and service_id then
    state.by_service[service_id] = ref

  elseif typ == TYPE_ROUTE and route_id then
    state.by_route[route_id] = ref

  elseif typ == TYPE_COMBINED and service_id and route_id then
    local routes = state.combined[service_id]

    if not routes then
      routes = {}
      state.combined[service_id] = routes
    end

    routes[route_id] = ref
  end
end


---
-- Build a combined filter list from 1-2 filter chain entities.
--
-- Disabled filter chains are skipped, and disabled filters are
-- skipped.
--
-- Returns `nil` if no enabled filters are found.
--
---@param service_chain? kong.db.schema.entities.wasm_filter_chain
---@param route_chain?   kong.db.schema.entities.wasm_filter_chain
---
---@return kong.db.schema.entities.wasm_filter[]?
local function build_filter_list(service_chain, route_chain)
  ---@type kong.db.schema.entities.wasm_filter[]|nil
  local combined
  local n = 0

  if service_chain and service_chain.enabled then
    for _, filter in ipairs(service_chain.filters) do
      if filter.enabled then
        n = n + 1
        combined = combined or {}
        combined[n] = filter
      end
    end
  end

  if route_chain and route_chain.enabled then
    for _, filter in ipairs(route_chain.filters) do
      if filter.enabled then
        n = n + 1
        combined = combined or {}
        combined[n] = filter
      end
    end
  end

  return combined
end


---
-- Unconditionally rebuild and return a new wasm state table from the db.
--
---@param  db                       table # kong.db
---@param  version                  any
---@param  old_state                kong.runloop.wasm.state
---@return kong.runloop.wasm.state? new_state
---@return string?                  err
local function rebuild_state(db, version, old_state)
  local route_chains = {}
  local service_chains_by_id = {}

  ---@type kong.runloop.wasm.state
  local state = {
    by_service = {},
    by_route = {},
    combined = {},
    version = version,
  }

  local all_chains = {}
  local page_size = db.wasm_filter_chains.max_page_size

  for chain, err in db.wasm_filter_chains:each(page_size) do
    if err then
      return nil, "failed iterating filter chains: " .. tostring(err)
    end

    if chain.enabled then
      local route_id = chain.route and chain.route.id
      local service_id = chain.service and chain.service.id

      local chain_type = service_id and TYPE_SERVICE or TYPE_ROUTE

      insert(all_chains, {
        type       = chain_type,
        service    = (chain_type == TYPE_SERVICE and chain) or nil,
        route      = (chain_type == TYPE_ROUTE and chain) or nil,
        service_id = service_id,
        route_id   = route_id,
      })

      if chain_type == TYPE_SERVICE then
        service_chains_by_id[service_id] = chain

      else
        insert(route_chains, chain)
      end
    end
  end

  local routes = db.routes
  local select_route = routes.select

  -- the only cache lookups here are for route entities,
  -- so use the core cache
  local cache = kong.core_cache


  for _, rchain in ipairs(route_chains) do
    local cache_key = routes:cache_key(rchain.route.id)

    local route, err = cache:get(cache_key, nil,
                                 select_route, routes, rchain.route)

    if err then
      return nil, "failed to load route for filter chain: " .. tostring(err)
    end

    local service_id = route and route.service and route.service.id
    local schain = service_id and service_chains_by_id[service_id]

    if schain then
      insert(all_chains, {
        type       = TYPE_COMBINED,
        service    = schain,
        route      = rchain,
        service_id = service_id,
        route_id   = route.id,
      })
    end
  end

  for _, chain in ipairs(all_chains) do
    local service_id = chain.service_id
    local route_id = chain.route_id

    local hash = hash_chain(chain.service, chain.route)
    local ref = get_chain_ref(old_state, chain.type, service_id, route_id)

    if ref then
      if ref.hash == hash then
        log(DEBUG, "reusing existing filter chain reference")

      else
        log(DEBUG, "filter chain has changed and will be rebuilt")
        ref = nil
      end
    end

    if not ref then
      local filters = build_filter_list(chain.service, chain.route)
      local c_plan, err = init_c_plan(filters)

      if err then
        return nil, "failed to initialize filter chain: " .. tostring(err)

      elseif not c_plan then
        log(DEBUG, "filter chain has no enabled filters")
      end

      ref = {
        hash = hash,
        type = chain.type,
        c_plan = c_plan,
      }
    end

    store_chain_ref(state, ref, chain.type, service_id, route_id)
  end

  return state
end


---
-- Replace the current filter chain state with a new one.
--
-- This function does not do any I/O or other yielding operations.
--
---@param new kong.runloop.wasm.state
local function set_state(new)
  if type(new) ~= "table" then
    error("bad argument #1 to 'set_state' (table expected, got " ..
          type(new) .. ")", 2)
  end

  local old = STATE

  if old.version == new.version then
    log(DEBUG, "called with new version that is identical to the last")
  end

  STATE = new
end


---
-- Conditionally rebuild and update the filter chain state.
--
-- If the current state matches the desired version, no update
-- will be performed.
--
---@param  new_version? string
---@return boolean?     ok
---@return string?      error
local function update_in_place(new_version)
  if not ENABLED then
    return true
  end

  new_version = new_version or get_version()
  local old = STATE

  if new_version == old.version then
    log(DEBUG, "filter chain state is already up-to-date, no changes needed")
    return true
  end

  local new, err = rebuild_state(kong.db, new_version, old)
  if not new then
    log(ERR, "failed rebuilding filter chain state: ", err)
    return nil, err
  end

  set_state(new)

  return true
end



---@param route?    { id: string }
---@param service?  { id: string }
---@return kong.runloop.wasm.filter_chain_reference?
local function get_request_filters(route, service)
  local service_id = service and service.id
  local route_id = route and route.id
  local state = STATE

  return get_chain_ref(state, TYPE_COMBINED, service_id, route_id)
      or get_chain_ref(state, TYPE_SERVICE, service_id)
      or get_chain_ref(state, TYPE_ROUTE, nil, route_id)
end


_M.get_version = get_version

_M.update_in_place = update_in_place

_M.set_state = set_state


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


---@return boolean? ok
---@return string?  error
function _M.init_worker()
  if not ENABLED then
    return true
  end

  local ok, err = update_in_place()
  if not ok then
    return nil, err
  end

  return true
end


---
-- Lookup and execute the filter chain that applies to the current request
-- (if any).
--
---@param ctx table # the request ngx.ctx table
function _M.attach_filter_chain(ctx)
  if not ENABLED then
    return
  end

  local chain = get_request_filters(ctx.route, ctx.service)

  if not chain then
    return
  end

  if not chain.c_plan then
    log(DEBUG, "no enabled filters in chain")
    return
  end

  local ok, err = proxy_wasm.attach(chain.c_plan)
  if not ok then
    log(ERR, "failed attaching filter chain to request: ", err)
    error(err)
  end
end


---
-- Unconditionally rebuild and return the current filter chain state.
--
-- This function is intended to be used in conjunction with `set_state()`
-- to perform an atomic update of the filter chain state alongside other
-- node updates:
--
-- ```lua
-- local new_state, err = wasm.rebuild_state()
-- if not new_state then
--   -- handle error
-- end
--
-- -- do some other things in preparation of an update
-- -- [...]
--
--
-- -- finally, swap in the new state
-- wasm.set_state(new_state)
-- ```
--
---@return kong.runloop.wasm.state? state
---@return string? error
function _M.rebuild_state()
  -- return the default/empty state
  if not ENABLED then
    return STATE
  end

  local old = STATE
  local version = get_version()

  return rebuild_state(kong.db, version, old)
end


function _M.enabled()
  return ENABLED
end


return _M
