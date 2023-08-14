local _M = {
  -- these filter lookup tables are created once and then reset/re-used when
  -- `wasm.init()` is called. This means other modules are permitted to stash
  -- a reference to them, which helps to avoid several chicken/egg dependency
  -- ordering issues.

  ---@type kong.configuration.wasm_filter[]
  filters = {},

  ---@type table<string, kong.configuration.wasm_filter>
  filters_by_name = {},

  ---@type string[]
  filter_names = {},
}


--- This represents a wasm module discovered by the conf_loader in
--- `kong.configuration.wasm_filters_path`
---
---@class kong.configuration.wasm_filter
---
---@field name string
---@field path string


local utils = require "kong.tools.utils"
local dns = require "kong.tools.dns"
local reports = require "kong.reports"
local clear_tab = require "table.clear"

---@module 'resty.wasmx.proxy_wasm'
local proxy_wasm

local kong = _G.kong
local ngx = ngx
local log = ngx.log
local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local CRIT = ngx.CRIT
local tostring = tostring
local ipairs = ipairs
local type = type
local assert = assert
local concat = table.concat
local insert = table.insert
local sha256 = utils.sha256_bin


local VERSION_KEY = "filter_chains:version"
local TTL_ZERO = { ttl = 0 }


---
-- Fetch the current version of the filter chain state from cache
--
---@return string
local function get_version()
  return kong.core_cache:get(VERSION_KEY, TTL_ZERO, utils.uuid)
end


---@alias kong.wasm.filter_chain_type
---| 0 # service
---| 1 # route
---| 2 # combined

local TYPE_SERVICE  = 0
local TYPE_ROUTE    = 1
local TYPE_COMBINED = 2

local STATUS_DISABLED = "wasm support is not enabled"
local STATUS_NO_FILTERS = "no wasm filters are available"
local STATUS_ENABLED = "wasm support is enabled"

local ENABLED = false
local STATUS = STATUS_DISABLED


local hash_chain
do
  local HASH_DISABLED = sha256("disabled")
  local HASH_NONE     = sha256("none")

  local buf = {}

  ---@param chain kong.db.schema.entities.filter_chain
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
  -- Generate a hash key for a filter chain from a service
  -- and route filter chain [entity] combo.
  --
  -- The result of this is used to invalidate cached filter chain
  -- plans.
  --
  ---@param service? kong.db.schema.entities.filter_chain
  ---@param route?   kong.db.schema.entities.filter_chain
  ---@return string
  function hash_chain(service, route)
    assert(service ~= nil or route ~= nil,
           "hash_chain() called with neither service nor route")

    return sha256(hash_chain_entity(service) .. hash_chain_entity(route))
  end
end


---@class kong.runloop.wasm.filter_chain_reference
---
---@field type          kong.wasm.filter_chain_type
---@field label         string
---@field hash          string
---@field c_plan        ffi.cdata*|nil
---
---@field service_chain kong.db.schema.entities.filter_chain|nil
---@field service_id    string|nil
---
---@field route_chain   kong.db.schema.entities.filter_chain|nil
---@field route_id      string|nil


---@class kong.runloop.wasm.state
local STATE = {
  -- mapping of service IDs to service filter chains
  --
  ---@type table<string, kong.runloop.wasm.filter_chain_reference>
  by_service = {},

  -- mapping of route IDs to route filter chains
  --
  ---@type table<string, kong.runloop.wasm.filter_chain_reference>
  by_route = {},

  -- two level mapping: the top level is indexed by service ID, and the
  -- secondary level is indexed by route ID
  --
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
---@param typ         kong.wasm.filter_chain_type
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

  else
    -- unreachable
    error("unknown filter chain type: " .. tostring(typ), 2)
  end

  return ref
end


---
-- Helper method for storing a new filter chain reference within
-- the state table.
--
---@param state       kong.runloop.wasm.state
---@param ref         kong.runloop.wasm.filter_chain_reference
local function store_chain_ref(state, ref)
  local typ = ref.type
  local service_id = ref.service_id
  local route_id = ref.route_id

  if typ == TYPE_SERVICE then
    assert(type(service_id) == "string",
           ref.label .. " chain has no service ID")

    state.by_service[service_id] = ref

  elseif typ == TYPE_ROUTE then
    assert(type(route_id) == "string",
           ref.label .. " chain has no route ID")

    state.by_route[route_id] = ref

  elseif typ == TYPE_COMBINED then
    assert(type(service_id) == "string" and type(route_id) == "string",
           ref.label .. " chain is missing a service ID or route ID")

    local routes = state.combined[service_id]

    if not routes then
      routes = {}
      state.combined[service_id] = routes
    end

    routes[route_id] = ref

  else
    -- unreachable
    error("unknown filter chain type: " .. tostring(typ), 2)
  end
end


---
-- Create a log-friendly string label for a filter chain reference.
--
---@param service_id? string
---@param route_id?   string
---@return string label
local function label_for(service_id, route_id)
  if service_id and route_id then
    return "combined " ..
           "service(" .. service_id .. "), " ..
           "route(" .. route_id .. ")"

  elseif service_id then
    return "service(" .. service_id .. ")"

  elseif route_id then
    return "route(" .. route_id .. ")"

  else
    -- unreachable
    error("can't compute a label for a filter chain with no route/service", 2)
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
---@param service_chain? kong.db.schema.entities.filter_chain
---@param route_chain?   kong.db.schema.entities.filter_chain
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
  ---@type kong.db.schema.entities.filter_chain[]
  local route_chains = {}

  ---@type table<string, kong.db.schema.entities.filter_chain>
  local service_chains_by_id = {}

  ---@type kong.runloop.wasm.state
  local state = {
    by_service = {},
    by_route = {},
    combined = {},
    version = version,
  }

  ---@type kong.runloop.wasm.filter_chain_reference[]
  local all_chain_refs = {}

  local page_size = db.filter_chains.max_page_size

  for chain, err in db.filter_chains:each(page_size) do
    if err then
      return nil, "failed iterating filter chains: " .. tostring(err)
    end

    if chain.enabled then
      local route_id = chain.route and chain.route.id
      local service_id = chain.service and chain.service.id

      local chain_type = service_id and TYPE_SERVICE or TYPE_ROUTE

      insert(all_chain_refs, {
        type           = chain_type,

        service_chain  = (chain_type == TYPE_SERVICE and chain) or nil,
        service_id     = service_id,

        route_chain    = (chain_type == TYPE_ROUTE and chain) or nil,
        route_id       = route_id,
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


  -- locate matching route/service chain entities to build combined
  -- filter chain references
  for _, rchain in ipairs(route_chains) do
    local cache_key = routes:cache_key(rchain.route.id)

    local route, err = cache:get(cache_key, nil,
                                 select_route, routes, rchain.route)

    if err then
      return nil, "failed to load route for filter chain " ..
                  rchain.id .. ": " .. tostring(err)
    end

    local service_id = route and route.service and route.service.id
    local schain = service_id and service_chains_by_id[service_id]

    if schain then
      insert(all_chain_refs, {
        type           = TYPE_COMBINED,

        service_chain  = schain,
        service_id     = service_id,

        route_chain    = rchain,
        route_id       = route.id,
      })
    end
  end

  for _, chain_ref in ipairs(all_chain_refs) do
    local service_id = chain_ref.service_id
    local route_id = chain_ref.route_id

    local new_chain_hash = hash_chain(chain_ref.service_chain, chain_ref.route_chain)
    local old_ref = get_chain_ref(old_state, chain_ref.type, service_id, route_id)
    local new_ref

    if old_ref then
      if old_ref.hash == new_chain_hash then
        new_ref = old_ref
        log(DEBUG, old_ref.label, ": reusing existing filter chain reference")

      else
        log(DEBUG, old_ref.label, ": filter chain has changed and will be rebuilt")
      end
    end


    if not new_ref then
      new_ref = chain_ref
      new_ref.label = label_for(service_id, route_id)

      local filters = build_filter_list(chain_ref.service_chain, chain_ref.route_chain)
      local c_plan, err = init_c_plan(filters)

      if err then
        return nil, "failed to initialize " .. new_ref.label ..
                    " filter chain: " .. tostring(err)

      elseif not c_plan then
        log(DEBUG, new_ref.label, " filter chain has no enabled filters")
      end

      new_ref.hash = new_chain_hash
      new_ref.c_plan = c_plan
    end

    store_chain_ref(state, new_ref)
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
local function get_filter_chain_for_request(route, service)
  local service_id = service and service.id
  local route_id = route and route.id
  local state = STATE

  return get_chain_ref(state, TYPE_COMBINED, service_id, route_id)
      or get_chain_ref(state, TYPE_SERVICE, service_id)
      or get_chain_ref(state, TYPE_ROUTE, nil, route_id)
end


---@param filters kong.configuration.wasm_filter[]|nil
local function set_available_filters(filters)
  clear_tab(_M.filters)
  clear_tab(_M.filters_by_name)
  clear_tab(_M.filter_names)

  if filters then
    for i, filter in ipairs(filters) do
      _M.filters[i] = filter
      _M.filters_by_name[filter.name] = filter
      _M.filter_names[i] = filter.name
    end
  end
end


---@param reason string
local function disable(reason)
  set_available_filters(nil)

  _G.dns_client = nil

  ENABLED = false
  STATUS = reason or STATUS_DISABLED
end


local function enable(kong_config)
  set_available_filters(kong_config.wasm_modules_parsed)

  -- setup a DNS client for ngx_wasm_module
  _G.dns_client = _G.dns_client or dns(kong_config)

  proxy_wasm = proxy_wasm or require "resty.wasmx.proxy_wasm"

  ENABLED = true
  STATUS = STATUS_ENABLED
end


_M.get_version = get_version

_M.update_in_place = update_in_place

_M.set_state = set_state

function _M.enable(filters)
  enable({
    wasm = true,
    wasm_modules_parsed = filters,
  })
end

_M.disable = disable


---@param kong_config table
function _M.init(kong_config)
  if kong_config.wasm then
    local filters = kong_config.wasm_modules_parsed

    if filters and #filters > 0 then
      reports.add_immutable_value("wasm_cnt", #filters)
      enable(kong_config)

    else
      disable(STATUS_NO_FILTERS)
    end

  else
    disable(STATUS_DISABLED)
  end
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


local function set_proxy_wasm_property(property, value)
  if not value then
    return
  end

  local ok, err = proxy_wasm.set_property(property, value)
  if not ok then
    log(ERR, "failed to set proxy-wasm '", property, "' property: ", err)
  end
end


---
-- Lookup and execute the filter chain that applies to the current request
-- (if any).
--
---@param ctx table # the request ngx.ctx table
function _M.attach(ctx)
  if not ENABLED then
    return
  end

  local chain = get_filter_chain_for_request(ctx.route, ctx.service)

  if not chain then
    -- no matching chain for this route/service
    return
  end

  if not chain.c_plan then
    -- all filters in this chain are disabled
    return
  end

  ctx.ran_wasm = true

  local ok, err = proxy_wasm.attach(chain.c_plan)
  if not ok then
    log(CRIT, "failed attaching ", chain.label, " filter chain to request: ", err)
    return kong.response.error(500)
  end

  set_proxy_wasm_property("kong.route_id", ctx.route and ctx.route.id)
  set_proxy_wasm_property("kong.service_id", ctx.service and ctx.service.id)

  ok, err = proxy_wasm.start()
  if not ok then
    log(CRIT, "failed to execute ", chain.label, " filter chain for request: ", err)
    return kong.response.error(500)
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


---@return boolean? ok
---@return string? error
function _M.status()
  if not ENABLED then
    return nil, STATUS
  end

  return true
end

return _M
